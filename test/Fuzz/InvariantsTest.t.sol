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
import {Handler} from "test/Fuzz/Handler.t.sol";
contract InvariantsTest is StdInvariant, Test {
    DeploySC deploySC;
    SCEngine scEngine;
    StableCoin stableCoin;
    HelperConfig helperConfig;
    Handler handler;

    address wethAddress;
    address wbtcAddress;
    address wethAddressPriceFeed;
    address wbtcAddressPriceFeed;

    function setUp() external {
        deploySC = new DeploySC();
        (stableCoin, scEngine, helperConfig) = deploySC.run();

        (
            wethAddress,
            wbtcAddress,
            wethAddressPriceFeed,
            wbtcAddressPriceFeed,

        ) = helperConfig.activeNetworkConfig();

        // console.log("WETH Address:", wethAddress);
        // console.log("WBTC Address:", wbtcAddress);

        handler = new Handler(scEngine, stableCoin);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = stableCoin.totalSupply();
        uint256 balanceOfWETH = IERC20(wethAddress).balanceOf(
            address(scEngine)
        );
        uint256 balanceOfWBTC = IERC20(wbtcAddress).balanceOf(
            address(scEngine)
        );

        uint256 wethValueInUSD = scEngine.getUSDValue(
            wethAddress,
            balanceOfWETH
        );
        uint256 wbtcValueInUSD = scEngine.getUSDValue(
            wbtcAddress,
            balanceOfWBTC
        );
        console.log("totalSupply", totalSupply);
        console.log("wethValueInUSD", wethValueInUSD);
        console.log("wbtcValueInUSD", wbtcValueInUSD);
        console.log("timesMintIsCalled", handler.timesMintIsCalled());

        assert(wbtcValueInUSD + wethValueInUSD >= totalSupply);
    }
}
