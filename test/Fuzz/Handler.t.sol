// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeploySC} from "script/DeploySC.s.sol";
import {SCEngine} from "src/SCEngine.sol";
import {StableCoin} from "src/StableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DeploySC deploySC;
    SCEngine scEngine;
    StableCoin stableCoin;
    HelperConfig helperConfig;

    ERC20Mock weth;
    ERC20Mock wbtc;
    address wethAddressPriceFeed;
    address wbtcAddressPriceFeed;
    uint256 constant MAX_VALUE = type(uint96).max;

    uint256 public timesMintIsCalled;
    address[] public addressesWithCollateralDeposited;

    constructor(SCEngine _scEngine, StableCoin _stableCoin) {
        scEngine = _scEngine;
        stableCoin = _stableCoin;

        address[] memory collateralTokens = scEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function mintSC(uint256 amountToMint, uint256 addressSeed) public {
        if (addressesWithCollateralDeposited.length == 0) {
            return;
        }
        address user = addressesWithCollateralDeposited[
            addressSeed % addressesWithCollateralDeposited.length
        ];
        (uint256 totalSCMinted, uint256 collateralValueInUSD) = scEngine
            .getAccountInformation(user);

        int256 maxSCToMint = (int256(collateralValueInUSD) / 2) -
            int256(totalSCMinted);

        if (maxSCToMint < 0) {
            return;
        }
        amountToMint = bound(amountToMint, 0, uint256(maxSCToMint));
        console.log("amountToMint", amountToMint);
        if (amountToMint == 0) {
            return;
        }
        vm.startPrank(user);
        scEngine.mintSC(amountToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_VALUE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(scEngine), amountCollateral);
        scEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        addressesWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = scEngine.getCollateralBalanceOfUser(
            address(collateral),
            msg.sender
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        scEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function _getCollateralFromSeed(
        uint256 _collateralSeed
    ) private view returns (ERC20Mock) {
        if (_collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
