// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IAssetManager.sol";
import "./IBalanceSheet.sol";
import "./ILiquidator.sol";

import "./AccessControl.sol";
import "./EnumerableSet.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title Liquidator: checks for accounts to be liquidated from the BalanceSheet
///                    and executes the liquidation on AssetManager
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract Liquidator is ILiquidator, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    address public immutable assetManagerAddress;
    address public immutable balanceSheetAddress;

    event AddedToLiquidationCandidates(address _account);
    event AddedToReadyForLiquidationCandidates(address _account);
    event RemovedFromLiquidationCandidates(address _account);
    event RemovedFromReadyForLiquidationCandidates(address _account);

    EnumerableSet.AddressSet private liquidationCandidates; // 1st time offenders - given a chance to improve health score
    EnumerableSet.AddressSet private readyForLiquidationCandidates; // 2nd time offenders - will be liquidated

    constructor(address _assetManagerAddress, address _balanceSheetAddress) {
        assetManagerAddress = _assetManagerAddress;
        balanceSheetAddress = _balanceSheetAddress;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice calls BalanceSheet to get a list of accounts to be liquidated
     *         and adds them to the liquidationCandidates set
     *         or readyForLiquidationCandidates set if they are already in the liquidationCandidates set
     * @dev only callable by the admin
     */
    function setLiquidationCandidates() public onlyAdmin {
        address[] memory liquidatables = IBalanceSheet(balanceSheetAddress)
            .getLiquidatables();

        // no liquidatable accounts
        // reset the existing liquidation candidates
        // we can't just reset the EnumerableSet
        // because it will corrupt the storage https://docs.openzeppelin.com/contracts/4.x/api/utils#EnumerableSet
        // we have to iterate through the existing set and remove each element
        if (liquidatables.length == 0) {
            address[] memory existingCandidates = EnumerableSet.values(
                liquidationCandidates
            );
            for (uint256 i = 0; i < existingCandidates.length; i++) {
                liquidationCandidates.remove(existingCandidates[i]);

                emit RemovedFromLiquidationCandidates(existingCandidates[i]);
            }
        } else {
            // there are liquidatable accounts
            for (uint256 i = 0; i < liquidatables.length; i++) {
                // if the account is already in the liquidationCandidates set
                // then we need to remove it from the set
                // and add it to the readyForLiquidationCandidates set
                if (
                    EnumerableSet.contains(
                        liquidationCandidates,
                        liquidatables[i]
                    )
                ) {
                    EnumerableSet.remove(
                        liquidationCandidates,
                        liquidatables[i]
                    );

                    emit RemovedFromLiquidationCandidates(liquidatables[i]);

                    EnumerableSet.add(
                        readyForLiquidationCandidates,
                        liquidatables[i]
                    );

                    emit AddedToReadyForLiquidationCandidates(liquidatables[i]);
                } else {
                    // if the account is not in the liquidationCandidates set
                    // then we need to add it to the set
                    liquidationCandidates.add(liquidatables[i]);

                    emit AddedToLiquidationCandidates(liquidatables[i]);
                }
            }
        }
    }

    /**
     * @notice iterates through the readyForLiquidationCandidates set and calls on Asset Manager to liquidate
     * @dev only callable by the admin
     */
    function executeLiquidations() public onlyAdmin {
        address[] memory candidates = EnumerableSet.values(
            readyForLiquidationCandidates
        );
        for (uint256 i = 0; i < candidates.length; i++) {
            IAssetManager(assetManagerAddress).liquidate(candidates[i]);

            // remove the account from the readyForLiquidationCandidates set
            EnumerableSet.remove(readyForLiquidationCandidates, candidates[i]);

            emit RemovedFromReadyForLiquidationCandidates(candidates[i]);
        }
    }

    /**
     * @notice returns the list of liquidation candidates
     * @return the list of liquidatable accounts
     */
    function getLiquidatableCandidates()
        public
        view
        returns (address[] memory)
    {
        return EnumerableSet.values(liquidationCandidates);
    }

    /**
     * @notice returns the list of ready for liquidation candidates
     * @return the list of ready for liquidation candidates
     */
    function getReadyForLiquidationCandidates()
        public
        view
        returns (address[] memory)
    {
        return EnumerableSet.values(readyForLiquidationCandidates);
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "Liquidator: only DefragSystemAdmin"
        );
        _;
    }
}

