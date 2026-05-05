// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract FeeSettings is Ownable {
    uint256 public feeBps;

    event FeeChanged(uint256 newFeeBps);

    constructor(address timelock, uint256 initialFeeBps) Ownable(timelock) {
        require(timelock != address(0), "timelock zero");
        require(initialFeeBps <= 10_000, "fee too high");
        feeBps = initialFeeBps;
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 10_000, "fee too high");
        feeBps = newFeeBps;
        emit FeeChanged(newFeeBps);
    }
}
