// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IAgent} from "./IAgent.sol";
import {IParam} from "./IParam.sol";

interface IRouter {
    event SignerAdded(address indexed signer);

    event SignerRemoved(address indexed signer);

    event FeeCollectorSet(address indexed feeCollector_);

    event PauserSet(address indexed pauser);

    event Paused();

    event Unpaused();

    event Execute(address indexed user, address indexed agent, uint256 indexed referralCode);

    event AgentCreated(address indexed agent, address indexed user);

    error NotReady();

    error InvalidPauser();

    error AlreadyPaused();

    error NotPaused();

    error InvalidFeeCollector();

    error InvalidNewPauser();

    error SignatureExpired(uint256 deadline);

    error InvalidSigner(address signer);

    error InvalidSignature();

    error AgentAlreadyCreated();

    function agentImplementation() external view returns (address);

    function agents(address user) external view returns (IAgent);

    function signers(address signer) external view returns (bool);

    function currentUser() external view returns (address);

    function feeCollector() external view returns (address);

    function pauser() external view returns (address);

    function owner() external view returns (address);

    function domainSeparator() external view returns (bytes32);

    function getAgent(address user) external view returns (address);

    function getCurrentUserAgent() external view returns (address, address);

    function calcAgent(address user) external view returns (address);

    function addSigner(address signer) external;

    function removeSigner(address signer) external;

    function setFeeCollector(address feeCollector_) external;

    function setPauser(address pauser_) external;

    function rescue(address token, address receiver, uint256 amount) external;

    function pause() external;

    function unpause() external;

    function execute(
        IParam.Logic[] calldata logics,
        address[] calldata tokensReturn,
        uint256 referralCode
    ) external payable;

    function executeWithSignature(
        IParam.LogicBatch calldata logicBatch,
        address signer,
        bytes calldata signature,
        address[] calldata tokensReturn,
        uint256 referralCode
    ) external payable;

    function newAgent() external returns (address);

    function newAgent(address user) external returns (address);
}

