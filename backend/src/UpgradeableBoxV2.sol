// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UpgradeableBoxV1} from "./UpgradeableBoxV1.sol";

contract UpgradeableBoxV2 is UpgradeableBoxV1 {
    function increment() external onlyOwner {
        _value += 1;
        emit ValueChanged(_value);
    }

    function version() external pure override returns (string memory) {
        return "V2";
    }
}
