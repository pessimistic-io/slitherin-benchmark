// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.9;

import "./PausableUpgradeable.sol";
import "./OFTUpgradeable.sol";

contract ChildWUSDR is PausableUpgradeable, OFTUpgradeable {
    address public migrator;

    function initialize(address lzEndpoint) public initializer {
        __Ownable_init();
        __Pausable_init();
        __OFTUpgradeable_init("Wrapped USDR", "wUSDR", lzEndpoint);
        migrator = msg.sender;
    }

    function setOwner(address _newOwner) external reinitializer(2) {
        _transferOwnership(_newOwner);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function setMigrator(address _migrator) external {
        require(msg.sender == migrator, "ChildWUSDR: not allowed");
        migrator = _migrator;
    }

    function mint(address _account, uint256 _amount) external {
        require(msg.sender == migrator, "ChildWUSDR: not migrator");
        _mint(_account, _amount);
    }

    ///
    /// LayerZero overrides
    ///

    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes calldata _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) public payable override whenNotPaused {
        _send(
            _from,
            _dstChainId,
            _toAddress,
            _amount,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }
}

