// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {StableCoin} from "src/StableCoin.sol";
import {SCEngine} from "src/SCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeploySC is Script {
    HelperConfig public helperConfig;
    address[] public _tokenAddresses;
    address[] public _priceFeedAddresses;
    address public s_owner = makeAddr("owner");

    function run() external returns (StableCoin, SCEngine, HelperConfig) {
        helperConfig = new HelperConfig();
        (
            address wethAddress,
            address wbtcAddress,
            address wethAddressPriceFeed,
            address wbtcAddressPriceFeed,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        _tokenAddresses = [wethAddress, wbtcAddress];
        _priceFeedAddresses = [wethAddressPriceFeed, wbtcAddressPriceFeed];

        vm.startBroadcast(deployerKey);
        StableCoin stableCoin = new StableCoin(
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        );
        SCEngine scEngine = new SCEngine(
            _tokenAddresses,
            _priceFeedAddresses,
            address(stableCoin)
        );
        stableCoin.transferOwnership(address(scEngine));

        vm.stopBroadcast();
        return (stableCoin, scEngine, helperConfig);
    }
}
