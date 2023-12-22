//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// Structs
import {OptionsPurchase, DepositPosition, Checkpoint} from "./AtlanticPutsPoolStructs.sol";

// Interfaces
import {IAtlanticPutsPool} from "./IAtlanticPutsPool.sol";

contract AtlanticsViewer {
    /**
     * @notice Get user options purchase positions
     * @param  _epoch             Epoch of the pool
     * @param  _pool              Address of the pool
     * @param  _user              Address of the user
     * @return _purchasePositions Options purchase positions of the user
     */
    function getUserOptionsPurchases(
        IAtlanticPutsPool _pool,
        uint256 _epoch,
        address _user
    ) external view returns (OptionsPurchase[] memory _purchasePositions) {
        _purchasePositions = new OptionsPurchase[](
            _pool.purchasePositionsCounter()
        );

        for (uint256 i; i < _purchasePositions.length; ) {
            OptionsPurchase memory purchasePosition = _pool
                .getOptionsPurchase(i);
            if (
                purchasePosition.user == _user &&
                purchasePosition.epoch == _epoch
            ) {
                _purchasePositions[i] = purchasePosition;
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Get user deposit positions
     * @param  _epoch            Epoch of the pool
     * @param  _pool             Address of the pool
     * @param  _user             Address of the user
     * @return _depositPositions Deposit positions of the user
     */
    function getUserDeposits(
        IAtlanticPutsPool _pool,
        uint256 _epoch,
        address _user
    ) external view returns (DepositPosition[] memory _depositPositions) {
        _depositPositions = new DepositPosition[](
            _pool.depositPositionsCounter()
        );

        for (uint256 i; i < _depositPositions.length; ) {
            DepositPosition memory depositPosition = _pool
                .getDepositPosition(i);
            if (
                depositPosition.depositor == _user &&
                depositPosition.epoch == _epoch
            ) {
                _depositPositions[i] = depositPosition;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
   * @notice Fetch Checkpoint data(type) for a given strike in a pool
   * @param  _pool         Address of the pool
   * @param  _epoch        Epoch of the pool
   * @param  _strike       Strike to query for (max-strikes pool accepts strikes)
   * @return _checkpoints  Array of checkpoints

   */
    function getEpochCheckpoints(
        IAtlanticPutsPool _pool,
        uint256 _epoch,
        uint256 _strike
    ) external view returns (Checkpoint[] memory _checkpoints) {
        return _pool.getEpochCheckpoints(_epoch, _strike);
    }

    /**
     * @notice Fetch strikes of a atlantic pool
     * @param _pool     Address of the pool
     * @param _epoch    Epoch of the pool
     * @return _strikes Array of strikes
     */
    function getEpochStrikes(
        IAtlanticPutsPool _pool,
        uint256 _epoch
    ) external view returns (uint256[] memory) {
        return _pool.getEpochStrikes(_epoch);
    }
}

