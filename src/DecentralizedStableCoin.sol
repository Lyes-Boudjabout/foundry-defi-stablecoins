// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Lyes-Boudjabout
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * @notice This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountToBurnCantBeZero();
    error DecentralizedStableCoin__InsufficientBalance();
    error DecentralizedStableCoin__AmountToBurnLessThanBalance();
    error DecentralizedStableCoin__CantMintForAddressZero();
    error DecentralizedStableCoin__MintAmountCantBeZero();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public virtual override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountToBurnCantBeZero();
        }
        if (balance <= 0) {
            revert DecentralizedStableCoin__InsufficientBalance();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__AmountToBurnLessThanBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external virtual onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__CantMintForAddressZero();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MintAmountCantBeZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
