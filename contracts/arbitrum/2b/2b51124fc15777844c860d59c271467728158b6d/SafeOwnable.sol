// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/* solhint-disable reason-string */

contract SafeOwnable {
    /* ▁▂▃▄▅▆▇█▉▊▋▌▍▎▏ STATE VARIABLES  ▏▎▍▌▋▊▉█▇▆▅▄▃▂▁ */

    address private _owner;
    address private _pendingOwner;

    /* ▁▂▃▄▅▆▇█▉▊▋▌▍▎▏ EVENTS  ▏▎▍▌▋▊▉█▇▆▅▄▃▂▁ */

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /* ▁▂▃▄▅▆▇█▉▊▋▌▍▎▏ CONSTRUCTOR  ▏▎▍▌▋▊▉█▇▆▅▄▃▂▁ */

    /// @notice ownership is assigned to `owner_` on construction
    constructor(address owner_) {
        _owner = owner_;
        emit OwnershipTransferred(address(0), _owner);
    }

    /* ▁▂▃▄▅▆▇█▉▊▋▌▍▎▏ MODIFIERS  ▏▎▍▌▋▊▉█▇▆▅▄▃▂▁ */

    /// @notice Only allows the `owner` to execute the function
    modifier onlyOwner() {
        require(msg.sender == _owner, "SafeOwnable::onlyOwner: caller is not the owner");
        _;
    }

    /* ▁▂▃▄▅▆▇█▉▊▋▌▍▎▏ VIEWS  ▏▎▍▌▋▊▉█▇▆▅▄▃▂▁ */

    /// @dev Returns the address of the current owner
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /// @dev Returns the address of the pending owner
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /* ▁▂▃▄▅▆▇█▉▊▋▌▍▎▏ EXTERNALS  ▏▎▍▌▋▊▉█▇▆▅▄▃▂▁ */

    /// @notice Transfers ownership to `newOwner`, either directly or pending claim by the new owner
    /// @dev Can only be invoked by the current `owner`
    /// @param newOwner Address of the new owner
    /// @param direct True if the new owner should be set immediately. False if the new owner needs to claim first
    function transferOwnership(address newOwner, bool direct) public virtual onlyOwner {
        if (direct) {
            // Checks
            require(newOwner != address(0), "SafeOwnable::transferOwnership: zero address");

            // Effects
            emit OwnershipTransferred(_owner, newOwner);
            _owner = newOwner;
            _pendingOwner = address(0);
        } else {
            // Effects
            _pendingOwner = newOwner;
        }
    }

    /// @notice Called by the pending owner to claim ownership
    function claimOwnership() public virtual {
        // Checks
        require(msg.sender == _pendingOwner, "SafeOwnable::claimOwnership: caller not pending owner");

        // Effects
        emit OwnershipTransferred(_owner, _pendingOwner);
        _owner = _pendingOwner;
        _pendingOwner = address(0);
    }

    /// @notice Irreversibly removes the contract owner. It will not be possible to call `onlyOwner` functions anymore
    /// @dev Can only be called by the current `owner`. It will also void any pending ownership changes
    function renounceOwnership() public virtual onlyOwner {
        // Effects
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
        _pendingOwner = address(0);
    }
}

