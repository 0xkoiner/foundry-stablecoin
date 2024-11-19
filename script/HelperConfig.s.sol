// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethAddress;
        address wbtcAddress;
        address wethAddressPriceFeed;
        address wbtcAddressPriceFeed;
        uint256 deployerKey;
    }
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 3000e8;
    int256 public constant BTC_USD_PRICE = 90000e8;
    uint256 public constant ANVIL_DEFAULT_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getNetworkConfigSepolia();
        } else {
            activeNetworkConfig = getOrCreateAnvilETHConfig();
        }
    }

    function getNetworkConfigSepolia()
        public
        view
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                wethAddress: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
                wbtcAddress: 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC,
                wethAddressPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wbtcAddressPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getOrCreateAnvilETHConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethAddress != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator wethAddressPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock wethAddress = new ERC20Mock(
            "WETH",
            "WETH",
            msg.sender,
            1000e8
        );
        MockV3Aggregator wbtcAddressPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        ERC20Mock wbtcAddress = new ERC20Mock(
            "WBTC",
            "WBTC",
            msg.sender,
            1000e8
        );

        vm.stopBroadcast();
        return
            NetworkConfig({
                wethAddress: address(wethAddress),
                wbtcAddress: address(wbtcAddress),
                wethAddressPriceFeed: address(wethAddressPriceFeed),
                wbtcAddressPriceFeed: address(wbtcAddressPriceFeed),
                deployerKey: ANVIL_DEFAULT_PRIVATE_KEY
            });
    }
}
