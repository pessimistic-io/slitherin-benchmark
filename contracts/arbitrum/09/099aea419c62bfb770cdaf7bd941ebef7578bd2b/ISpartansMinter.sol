//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.18;

import "./ISpartans.sol";

interface ISpartansMinter {
    enum State {
        NOT_STARTED,
        WHITELIST_MINT,
        PUBLIC_MINT,
        FINISHED
    }

    error WalletLimitExceeded();
    error TokensLimitExceeded();
    error WrongState(State expected, State current);
    error WrongMsgValue(uint256 expected, uint256 value);
    error UserNotWhitelisted();
    error NothingToClaim();
    error WithdrawFailure();
    error TeamTokensAlreadyMinted();

    event TokensMinted(address indexed by, State indexed state, uint256 amount);

    function state() external view returns (State);

    function isWhitelistMinting() external view returns (bool);

    function isPublicMinting() external view returns (bool);

    function whitelistMintingEndTimestamp() external view returns (uint256);

    function publicMintingEndTimestamp() external view returns (uint256);

    function allTokensMinted() external view returns (bool);

    function publicMint(uint256 amount) external payable;

    function whitelistMint(
        uint256 amount,
        bytes32[] calldata proof_
    ) external payable;

    function claim() external;

    function withdraw() external;

    function spartans() external view returns (ISpartans);
}

