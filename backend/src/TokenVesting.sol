// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract TokenVesting {
    error ZeroAddress();
    error CliffLongerThanDuration();
    error NoTokensDue();

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable duration;
    uint64 public immutable cliff;
    uint256 public released;

    constructor(address token_, address beneficiary_, uint64 start_, uint64 duration_, uint64 cliff_) {
        if (token_ == address(0) || beneficiary_ == address(0)) revert ZeroAddress();
        if (cliff_ > duration_) revert CliffLongerThanDuration();
        token = IERC20(token_);
        beneficiary = beneficiary_;
        start = start_;
        duration = duration_;
        cliff = cliff_;
    }

    function release() external returns (uint256 amount) {
        amount = releasable();
        if (amount == 0) revert NoTokensDue();
        released += amount;
        token.transfer(beneficiary, amount);
    }

    function releasable() public view returns (uint256) {
        return vestedAmount(block.timestamp) - released;
    }

    function vestedAmount(uint256 timestamp) public view returns (uint256) {
        uint256 totalAllocation = token.balanceOf(address(this)) + released;
        if (timestamp < start + cliff) return 0;
        if (timestamp >= start + duration) return totalAllocation;
        return (totalAllocation * (timestamp - start)) / duration;
    }
}
