// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {StableCoin} from "src/StableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Contract Engine for stablecoim
/// @author 0xKoiner
/// @notice The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg
/// @notice This stablecoin has the properties: Exogenous Collateral | Dollar Pegged | Algoritmically Stable
/// @notice It is similar to DAI if DAI had no governance, no fees and was only backed be WETH & WBTC
/// @notice Our SC system should always be "overcollateralized". At no point, should the value of all collateral <= the $value of all the SC
/// @dev This contract is core of the SC System. It habdles all the logic for mining and redeeming of SC, as well as depositing & withdrawing collateral
/// @dev This contract is VERY loosely based on the MakerDAO DSS (DAI)
contract SCEngine is ReentrancyGuard {
    /** Errors */
    error SCEngine__NeedsMoreThanZero(uint256 _amount);
    error SCEngine__LengthOfArraysNotEq();
    error SCEngine__SCNotAllowed(address _addressOfToken);
    error SCEngine__NotSuccessTransferCollateralTokens();
    error SCEngine__ZeroAddress();
    error SCEngine__BreaksHealthFactor(uint256 _healthFactor);
    error SCEngine__MintFailed();
    error SCEngine__HealthFactorOK(uint256 _healthFactor);
    error SCEngine__HealthFactorNotImproved(uint256 _healthFactor);

    /** State Variables */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant WAD = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountSCMinted) private s_SCMinted;
    address[] private s_addressesTokenCollateral;
    StableCoin private immutable i_scAddress;

    /** Events */
    event CollateralDeposited(
        address indexed _sender,
        address indexed _tokenCollateralAddress,
        uint256 indexed _amount
    );

    event CollateralRedeemed(
        address indexed _sender,
        address indexed _tokenCollateralAddress,
        uint256 indexed _amount
    );
    event CollateralRedeemedByLiquidator(
        address indexed _from,
        address indexed _to,
        address indexed _tokenCollateralAddress,
        uint256 _amount
    );

    /** Modifiers */
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert SCEngine__NeedsMoreThanZero(_amount);
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeed[_tokenAddress] == address(0)) {
            revert SCEngine__SCNotAllowed(_tokenAddress);
        }
        _;
    }

    modifier zeroAddress(address _userAddress) {
        if (_userAddress == address(0)) {
            revert SCEngine__ZeroAddress();
        }
        _;
    }

    /** Functions */
    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        address _scAddress
    ) {
        uint256 lengthOfArray = _tokenAddresses.length;

        if (lengthOfArray != _priceFeedAddresses.length) {
            revert SCEngine__LengthOfArraysNotEq();
        }

        for (uint256 i; i < lengthOfArray; i++) {
            s_priceFeed[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_addressesTokenCollateral.push(_tokenAddresses[i]);
        }

        i_scAddress = StableCoin(_scAddress);
    }

    /**
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of collateral to deposit
     * @param _amountSCToMint The amount of stablecoin to mint
     * @dev depositCollateralAndMintSC The function depositinig and minting in one transaction
     */
    function depositCollateralAndMintSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountSCToMint
    )
        external
        isAllowedToken(_tokenCollateralAddress)
        moreThanZero(_amountCollateral)
        moreThanZero(_amountSCToMint)
    {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintSC(_amountSCToMint);
    }

    /**
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral
    )
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            _tokenCollateralAddress
        ] += _amountCollateral;

        emit CollateralDeposited(
            msg.sender,
            _tokenCollateralAddress,
            _amountCollateral
        );

        bool success = IERC20(_tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            _amountCollateral
        );

        if (!success) {
            revert SCEngine__NotSuccessTransferCollateralTokens();
        }
    }

    /**
     * @notice This function burn and redeem in one transaction
     * @param _tokenCollateralAddress Collateral token Address
     * @param _amountCollateral The amount of collateral to redeem
     * @param _amountSCToBurn The amount of stablecoin to burn
     */
    function redeemCollateralForSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountSCToBurn
    )
        external
        moreThanZero(_amountSCToBurn)
        isAllowedToken(_tokenCollateralAddress)
    {
        burnSC(_amountSCToBurn);
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
    }

    /**
     * @notice This function burn and redeem collateral tokens
     * @param _tokenCollateralAddress Collateral token Address
     * @param _amountCollateral The amount of collateral to redeem
     */
    function redeemCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral
    )
        public
        moreThanZero(_amountCollateral)
        nonReentrant
        isAllowedToken(_tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][
            _tokenCollateralAddress
        ] -= _amountCollateral;

        emit CollateralRedeemed(
            msg.sender,
            _tokenCollateralAddress,
            _amountCollateral
        );

        bool success = IERC20(_tokenCollateralAddress).transfer(
            msg.sender,
            _amountCollateral
        );

        if (!success) {
            revert SCEngine__NotSuccessTransferCollateralTokens();
        }

        _revertIfHealthFactoryIsBroken(msg.sender);
    }

    /**
     * @notice They must have more collateral value than the minimum threshold
     * @param _amountSCToMint The amount of stablecoin to mint
     */
    function mintSC(
        uint256 _amountSCToMint
    ) public moreThanZero(_amountSCToMint) nonReentrant {
        s_SCMinted[msg.sender] += _amountSCToMint;
        _revertIfHealthFactoryIsBroken(msg.sender);
        bool minted = i_scAddress.mint(msg.sender, _amountSCToMint);
        if (!minted) {
            revert SCEngine__MintFailed();
        }
    }

    /**
     * @notice This function burn stabelcoins
     * @param _amountSCToBurn The amount of stablecoin to burn
     */
    function burnSC(
        uint256 _amountSCToBurn
    ) public moreThanZero(_amountSCToBurn) zeroAddress(msg.sender) {
        s_SCMinted[msg.sender] -= _amountSCToBurn;
        bool success = i_scAddress.transferFrom(
            msg.sender,
            address(this),
            _amountSCToBurn
        );
        if (!success) {
            revert SCEngine__NotSuccessTransferCollateralTokens();
        }
        i_scAddress.burn(_amountSCToBurn);
    }

    /**
     * @notice This function liquidate users with health factor >1
     * @notice You can partially liquidate a user
     * @notice You will get bonus for liquidate
     * @notice The known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incetive the liquidators
     * @param _tokenCollateralAddress The ERC20 token collateral to liquidate from the user
     * @param _user The user who broke health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param _debtToCover The amount of stablecoin want to burn to improve the user health factor
     */
    function liquidate(
        address _tokenCollateralAddress,
        address _user,
        uint256 _debtToCover
    )
        external
        isAllowedToken(_tokenCollateralAddress)
        moreThanZero(_debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(_user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert SCEngine__HealthFactorOK(startingUserHealthFactor);
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(
            _tokenCollateralAddress,
            _debtToCover
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            _tokenCollateralAddress,
            totalCollateralToRedeem,
            _user,
            msg.sender
        );
        _burnSC(_debtToCover, _user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(_user);

        if (endingUserHealthFactor <= MIN_HEALTH_FACTOR) {
            revert SCEngine__HealthFactorNotImproved(startingUserHealthFactor);
        }
        _revertIfHealthFactoryIsBroken(msg.sender);
    }

    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }

    /**
     * @notice This function burn stabelcoins only for liquidators
     * @param _amountSCToBurn The amount of stablecoin to burn
     * @dev Low-level private function
     */
    function _burnSC(
        uint256 _amountSCToBurn,
        address _onBehalfOf,
        address _scFrom
    ) private moreThanZero(_amountSCToBurn) zeroAddress(msg.sender) {
        s_SCMinted[_onBehalfOf] -= _amountSCToBurn;
        bool success = i_scAddress.transferFrom(
            _scFrom,
            address(this),
            _amountSCToBurn
        );
        if (!success) {
            revert SCEngine__NotSuccessTransferCollateralTokens();
        }
        i_scAddress.burn(_amountSCToBurn);
    }

    /**
     * @notice This function burn and redeem collateral tokens for liquidators only
     * @param _tokenCollateralAddress Collateral token Address
     * @param _amountCollateral The amount of collateral to redeem
     */
    function _redeemCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        address _from,
        address _to
    )
        private
        moreThanZero(_amountCollateral)
        nonReentrant
        isAllowedToken(_tokenCollateralAddress)
    {
        s_collateralDeposited[_from][
            _tokenCollateralAddress
        ] -= _amountCollateral;

        emit CollateralRedeemedByLiquidator(
            _from,
            _to,
            _tokenCollateralAddress,
            _amountCollateral
        );

        bool success = IERC20(_tokenCollateralAddress).transfer(
            _to,
            _amountCollateral
        );

        if (!success) {
            revert SCEngine__NotSuccessTransferCollateralTokens();
        }

        _revertIfHealthFactoryIsBroken(_from);
    }

    function _getAccountInfo(
        address _user
    ) private view returns (uint256, uint256) {
        return (s_SCMinted[_user], getAccountCollateralValueInUSD(_user));
    }

    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalSCMinted, uint256 collateralValueInUSD) = _getAccountInfo(
            _user
        );
        return _calculateHealthFactor(totalSCMinted, collateralValueInUSD);
    }

    function _calculateHealthFactor(
        uint256 _totalSCMinted,
        uint256 _collateralValueInUSD
    ) internal pure returns (uint256) {
        if (_totalSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (_collateralValueInUSD *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * 1e18) / _totalSCMinted;
    }

    function _revertIfHealthFactoryIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert SCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function getAccountCollateralValueInUSD(
        address _user
    ) public view zeroAddress(_user) returns (uint256 totalCollateralInUSD) {
        uint256 arrayLength = s_addressesTokenCollateral.length;

        for (uint256 i; i < arrayLength; i++) {
            address tokenCollateralAddres = s_addressesTokenCollateral[i];
            uint256 amoutOfCollateral = s_collateralDeposited[_user][
                tokenCollateralAddres
            ];
            totalCollateralInUSD += getUSDValue(
                tokenCollateralAddres,
                amoutOfCollateral
            );
        }

        return totalCollateralInUSD;
    }

    function getUSDValue(
        address _tokenAddress,
        uint256 _amount
    ) public view isAllowedToken(_tokenAddress) returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[_tokenAddress]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / WAD;
    }

    function getTokenAmountFromUSD(
        address _tokenCollateralAddress,
        uint256 _debtToCover
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[_tokenCollateralAddress]
        );

        (, int256 price, , , ) = priceFeed.latestRoundData();

        return
            (_debtToCover * WAD) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
    function getAccountInformation(
        address _user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInfo(_user);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_addressesTokenCollateral;
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
