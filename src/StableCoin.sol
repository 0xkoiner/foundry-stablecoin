// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Contract for stablecoim
/// @author 0xKoiner
/// @notice Collateral: Exogenous (ETH & BTC)
/// @notice Minting: Algorithmic
/// @notice Relative Stability: Pegged to USD
/// @dev This is the contract meant to be governed by SCEngine.sol - This contract is just ERC20 implementation of our stablecoin system
contract StableCoin is ERC20Burnable, Ownable {
    /**
     * Errors
     */
    error StableCoin__MustBeMoreThanZero(uint256 _amount);
    error StableCoin__BurnAmountExceedsBalance(uint256 _amount);
    error StableCoin__NotAllowedAddressZero();

    /**
     * @param _owner Pass the owner of the contract to access this contract functions
     * @dev Init ERC20 constructor by token name and symbol
     */
    constructor(address _owner) ERC20("StableCoin", "SC") Ownable(_owner) {}

    /**
     * @param _amount Amount of tokens to burn
     * @dev Burn its means the tokens will send to address(0)
     * @dev The function override the function in ERC20Burnable contract
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableCoin__MustBeMoreThanZero(_amount);
        }
        if (balance < _amount) {
            revert StableCoin__BurnAmountExceedsBalance(_amount);
        }
        super.burn(_amount);
    }

    /**
     * @param _to Address who will get minted tokens
     * @param _amount Amount of tokens to mint
     * @dev Minting tokens and add the amount to totalSupply(). Mapping the amount of tokens to address in _to
     * @return true If the _mint(_to, _amount); done the function will return true
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoin__NotAllowedAddressZero();
        }
        if (_amount <= 0) {
            revert StableCoin__MustBeMoreThanZero(_amount);
        }

        _mint(_to, _amount);
        return true;
    }
}
