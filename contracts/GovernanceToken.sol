// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;

    constructor(
        address teamWallet,
        address treasuryWallet,
        address communityWallet,
        address liquidityWallet
    ) ERC20("Farmers Market Governance Token", "FMGT") ERC20Permit("Farmers Market Governance Token") Ownable(msg.sender) {
        require(teamWallet != address(0), "team wallet zero");
        require(treasuryWallet != address(0), "treasury wallet zero");
        require(communityWallet != address(0), "community wallet zero");
        require(liquidityWallet != address(0), "liquidity wallet zero");

        _mint(teamWallet, (INITIAL_SUPPLY * 40) / 100);
        _mint(treasuryWallet, (INITIAL_SUPPLY * 30) / 100);
        _mint(communityWallet, (INITIAL_SUPPLY * 20) / 100);
        _mint(liquidityWallet, (INITIAL_SUPPLY * 10) / 100);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
