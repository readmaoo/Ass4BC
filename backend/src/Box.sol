// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract Box is Ownable {
    uint256 private value;

    event ValueChanged(uint256 newValue);

    constructor(address timelock) Ownable(timelock) {
        require(timelock != address(0), "timelock zero");
    }

    function store(uint256 newValue) external onlyOwner {
        value = newValue;
        emit ValueChanged(newValue);
    }

    function retrieve() external view returns (uint256) {
        return value;
    }
}
