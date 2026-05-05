// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract UpgradeableBoxV1 {
    address private _owner;
    uint256 internal _value;
    bool private _initialized;

    event Initialized(address indexed owner);
    event ValueChanged(uint256 newValue);
    event ImplementationUpgraded(address indexed newImplementation);

    modifier onlyOwner() {
        require(msg.sender == _owner, "Only owner");
        _;
    }

    function initialize(address initialOwner) external {
        require(!_initialized, "Already initialized");
        require(initialOwner != address(0), "Owner zero");

        _owner = initialOwner;
        _initialized = true;

        emit Initialized(initialOwner);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function store(uint256 newValue) external onlyOwner {
        _value = newValue;
        emit ValueChanged(newValue);
    }

    function retrieve() external view returns (uint256) {
        return _value;
    }

    function version() external pure virtual returns (string memory) {
        return "V1";
    }

    function upgradeTo(address newImplementation) external onlyOwner {
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
        emit ImplementationUpgraded(newImplementation);
    }
}
