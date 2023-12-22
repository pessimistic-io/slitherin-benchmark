// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./BurnableOFTUpgradeable.sol";

contract FbDaoToken is BurnableOFTUpgradeable {
    address private _pool;
    uint256 private _totalBurned;

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

    function totalBurned() external view returns (uint256) {
        return _totalBurned + 23708509772447884209;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function burn(uint256 _amount) external virtual override {
        burnFrom(msg.sender, _amount);
    }

    function burnFrom(address _account, uint256 _amount) public virtual override {
        _totalBurned += _amount;
        super.burnFrom(_account, _amount);
    }

    /* ========== EVENTS ========== */
    event PoolUpdate(address indexed newPool);
}

