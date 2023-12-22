// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./BurnableOFTUpgradeable.sol";

contract FbDaoToken is BurnableOFTUpgradeable {
    address private _pool;

    /* ========== GOVERNANCE ========== */
    function setPool(address _newPool) external onlyOwner {
        _pool = _newPool;
        emit PoolUpdate(_newPool);
    }

    /* ========== VIEWS ========== */
    function circulatingSupply() public view virtual override returns (uint256) {
        unchecked {
            return totalSupply() - balanceOf(_pool);
        }
    }

    function pool() external view virtual returns (address) {
        return _pool;
    }

    /* ========== EVENTS ========== */
    event PoolUpdate(address indexed newPool);
}

