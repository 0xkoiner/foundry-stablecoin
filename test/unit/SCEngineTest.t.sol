// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {DeploySC} from "script/DeploySC.s.sol";
import {Test} from "forge-std/Test.sol";
import {SCEngine} from "src/SCEngine.sol";
import {StableCoin} from "src/StableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract SCEngineTest is Test {
    HelperConfig public helperConfig;
    StableCoin public stableCoin;
    SCEngine public scEngine;
    DeploySC public deploySC;
    address wethAddress;
    address wbtcAddress;
    address wethAddressPriceFeed;
    address wbtcAddressPriceFeed;
    uint256 amountCollateral = 10 ether;

    address public addressA = makeAddr("addressA");

    modifier depositedCollateral() {
        vm.startPrank(addressA);
        ERC20Mock(wethAddress).approve(address(scEngine), amountCollateral);
        scEngine.depositCollateral(wethAddress, amountCollateral);
        vm.stopPrank();
        _;
    }

    function setUp() external {
        deploySC = new DeploySC();
        (stableCoin, scEngine, helperConfig) = deploySC.run();
        (
            wethAddress,
            wbtcAddress,
            wethAddressPriceFeed,
            wbtcAddressPriceFeed,

        ) = helperConfig.activeNetworkConfig();
        vm.startPrank(address(scEngine));
        ERC20Mock(wethAddress).mint(addressA, 2e18);
        vm.stopPrank();
    }

    function testreturnCorrectUSDValueOfETH() external view {
        uint256 usdValue = scEngine.getUSDValue(wethAddress, 2);

        assertEq(usdValue, 6000);
    }

    function testGetTokenAmountFromUSD() external view {
        uint256 usdAmount = 300 ether;
        uint256 expectedWETH = 0.1 ether;
        uint256 actualWETH = scEngine.getTokenAmountFromUSD(
            wethAddress,
            usdAmount
        );
        assertEq(expectedWETH, actualWETH);
    }

    function testreturnCorrectUSDValueOfBTC() external view {
        uint256 usdValue = scEngine.getUSDValue(wbtcAddress, 3);

        assertEq(usdValue, 270000);
    }

    function testRevertsIfCollateralZero() external {
        vm.startPrank(addressA);
        ERC20Mock(wethAddress).approve(address(scEngine), 10e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                SCEngine.SCEngine__NeedsMoreThanZero.selector,
                0
            )
        );
        scEngine.depositCollateral(wethAddress, 0);
        vm.stopPrank();
    }

    function testDepositWETHCollateral() external {
        vm.startPrank(addressA);
        ERC20Mock(wethAddress).approve(address(scEngine), 2e18);
        scEngine.depositCollateral(wethAddress, 2e18);
        vm.stopPrank();

        uint256 totalCollateralInUSD = scEngine.getAccountCollateralValueInUSD(
            addressA
        );
        assertEq(totalCollateralInUSD, 6000e18);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function testRevertsIfTokensLengthDoesntMatchPriceFeeds() external {
        tokenAddresses.push(wethAddress);
        priceFeedAddresses.push(wethAddressPriceFeed);
        priceFeedAddresses.push(wbtcAddressPriceFeed);

        vm.expectRevert(SCEngine.SCEngine__LengthOfArraysNotEq.selector);
        new SCEngine(tokenAddresses, priceFeedAddresses, address(stableCoin));
    }

    function testRevertsWithNotAllowedCollateral() external {
        ERC20Mock notAllowedCollateralToken = new ERC20Mock(
            "notAllowedCollateralToken",
            "NACT",
            addressA,
            20 ether
        );

        vm.startPrank(addressA);
        notAllowedCollateralToken.approve(address(scEngine), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                SCEngine.SCEngine__SCNotAllowed.selector,
                address(notAllowedCollateralToken)
            )
        );
        scEngine.depositCollateral(address(notAllowedCollateralToken), 1 ether);
        vm.stopPrank();
    }
}
