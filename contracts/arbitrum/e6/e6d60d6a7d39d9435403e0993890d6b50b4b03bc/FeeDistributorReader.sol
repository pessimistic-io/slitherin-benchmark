
//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";
import "./MerkleProof.sol";

import "./IFeeDistributor.sol";

/**
 * @title FeeDistributorReader is a peripheral helper contract to read the FeeDistributor
 * @author dospore
 */
contract FeeDistributorReader {

    /**
     * @notice Check all claimed weeks from 0 to _weeks
     * @param _feeDistributor address
     * @param _account to check claimed weeks
     * @param _weeks number of weeks to check
     * @return a boolean array representing claimed weeks
     */
    function getUserClaimed(
        address _feeDistributor,
        address _account,
        uint256 _weeks
    ) public view returns (bool[] memory) {
        IFeeDistributor feeDistributor = IFeeDistributor(_feeDistributor);

        bool[] memory claimed = new bool[](_weeks);

        for (uint256 i = 0; i < _weeks; i++) {
            claimed[i] = feeDistributor.claimed(i, _account);
        }

        return claimed;
    }
}


