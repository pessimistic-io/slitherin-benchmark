// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {IERC20} from "./IERC20.sol";
import {IERC165} from "./IERC165.sol";

/// @notice Facilitates fundraising round.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/IFundraisingRoundManager.sol)
interface IFundraisingRoundManager is IERC165 {
    struct FundraisingRoundData {
        // Contract address of token denominating funds sought.
        IERC20 fundingToken;
        // Funds raised sent to this address.
        address payableTo;
        // Account authorized to add investors to the round.
        address manager;
    }

    error FundraisingRoundManager__NotManager();
    error FundraisingRoundManager__Active();
    error FundraisingRoundManager__NotActive();
    error FundraisingRoundManager__NotIssuing();
    error FundraisingRoundManager__InvalidCapitalizationManager(address account);

    function fundraisingRoundData(address shareToken) external view returns (FundraisingRoundData memory);

    /**
     * @notice Create new fundraising round, creates new token
     * @dev Create derivative token and store pricing info. Only callable by owner.
     * Once called, outstanding SAFEs can attempt to redeem rights
     * Round requires companyShareToken to set seriesAddress as operator
     * Issuance requires enough authorized shares to be held by this contract
     */
    function createRound(address shareToken, FundraisingRoundData calldata roundData) external;

    function invest(address shareToken, uint256 funds) external returns (uint256);

    function close(address shareToken) external;
}

