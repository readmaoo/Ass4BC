// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FeeSettings is Ownable {
    uint256 public feeBps;
    uint256 public constant MAX_FEE_BPS = 1_000;

    event FeeChanged(uint256 oldFeeBps, uint256 newFeeBps);

    constructor(address timelock, uint256 initialFeeBps) Ownable(timelock) {
        require(timelock != address(0), "timelock zero");
        require(initialFeeBps <= MAX_FEE_BPS, "fee too high");
        feeBps = initialFeeBps;
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "fee too high");
        uint256 oldFeeBps = feeBps;
        feeBps = newFeeBps;
        emit FeeChanged(oldFeeBps, newFeeBps);
    }
}
