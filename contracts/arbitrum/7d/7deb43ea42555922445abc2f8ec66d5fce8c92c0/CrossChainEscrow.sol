// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EIP712} from "./EIP712.sol";
import {SignatureVerifier} from "./SignatureVerifier.sol";

contract CrossChainEscrow is EIP712, SignatureVerifier {
    // --- Structs ---

    struct Request {
        bool isCollectionRequest;
        address maker;
        address solver;
        address token;
        uint256 tokenId;
        uint256 amount;
        uint256 price;
        address recipient;
        uint256 chainId;
        uint256 deadline;
        uint256 salt;
    }

    struct RequestStatus {
        bool isExecuted;
        bool isPrevalidated;
    }

    struct Withdraw {
        address solver;
        address user;
        uint256 amount;
        uint256 deadline;
        uint256 salt;
    }

    struct WithdrawStatus {
        bool isExecuted;
    }

    // --- Events ---

    event Deposited(address user, address solver, uint256 amount);

    event RequestExecuted(bytes32 requestHash);
    event RequestPrevalidated(bytes32 requestHash, Request request);

    event WithdrawExecuted(
        bytes32 withdrawHash,
        address user,
        address solver,
        uint256 amount
    );

    // --- Errors ---

    error RequestIsExecuted();
    error RequestIsExpired();
    error RequestIsPrevalidated();

    error WithdrawIsExecuted();
    error WithdrawIsExpired();

    error Unauthorized();
    error UnsuccessfulCall();

    // --- Fields ---

    bytes32 public immutable REQUEST_TYPEHASH;
    bytes32 public immutable WITHDRAW_TYPEHASH;

    // Keep track of the user's deposited balance per solver
    mapping(address => mapping(address => uint256)) public perSolverBalance;

    // Keep track of request and withdraw statuses
    mapping(bytes32 => RequestStatus) public requestStatus;
    mapping(bytes32 => WithdrawStatus) public withdrawStatus;

    // --- Constructor ---

    constructor() EIP712("CrossChainEscrow", "1") {
        REQUEST_TYPEHASH = keccak256(
            abi.encodePacked(
                "Request(",
                "bool isCollectionRequest,",
                "address maker,",
                "address solver,",
                "address token,",
                "uint256 tokenId,",
                "uint256 amount,",
                "uint256 price,",
                "address recipient,",
                "uint256 chainId,",
                "uint256 deadline,",
                "uint256 salt"
                ")"
            )
        );

        WITHDRAW_TYPEHASH = keccak256(
            abi.encodePacked(
                "Withdraw(",
                "address solver,",
                "address user,",
                "uint256 amount,",
                "uint256 deadline,",
                "uint256 salt",
                ")"
            )
        );
    }

    // --- Public methods ---

    function deposit(address solver) public payable {
        perSolverBalance[msg.sender][solver] += msg.value;

        emit Deposited(msg.sender, solver, msg.value);
    }

    function prevalidate(Request memory request) public {
        address maker = request.maker;

        if (msg.sender != maker) {
            revert Unauthorized();
        }

        bytes32 requestHash = getRequestHash(request);
        RequestStatus memory status = requestStatus[requestHash];
        if (status.isExecuted) {
            revert RequestIsExecuted();
        }
        if (status.isPrevalidated) {
            revert RequestIsPrevalidated();
        }

        requestStatus[requestHash].isPrevalidated = true;

        emit RequestPrevalidated(requestHash, request);
    }

    function depositAndPrevalidate(
        address solver,
        Request calldata request
    ) external payable {
        deposit(solver);
        prevalidate(request);
    }

    function executeWithdraw(
        Withdraw calldata withdraw,
        bytes calldata signature
    ) external {
        address solver = withdraw.solver;
        address user = withdraw.user;
        uint256 amount = withdraw.amount;

        if (msg.sender != user) {
            revert Unauthorized();
        }

        if (withdraw.deadline < block.timestamp) {
            revert WithdrawIsExpired();
        }

        bytes32 withdrawHash = getWithdrawHash(withdraw);
        WithdrawStatus memory status = withdrawStatus[withdrawHash];
        if (status.isExecuted) {
            revert WithdrawIsExecuted();
        }

        bytes32 eip712Hash = getEIP712Hash(withdrawHash);
        verifySignature(solver, eip712Hash, signature);

        withdrawStatus[withdrawHash].isExecuted = true;

        perSolverBalance[user][solver] -= amount;
        send(user, amount);

        emit WithdrawExecuted(withdrawHash, user, solver, amount);
    }

    // --- Solver methods ---

    function executeRequest(
        Request calldata request,
        bytes calldata signature
    ) external {
        address solver = request.solver;
        address maker = request.maker;
        uint256 price = request.price;

        if (msg.sender != solver) {
            revert Unauthorized();
        }

        if (request.deadline < block.timestamp) {
            revert RequestIsExpired();
        }

        bytes32 requestHash = getRequestHash(request);
        RequestStatus memory status = requestStatus[requestHash];
        if (status.isExecuted) {
            revert RequestIsExecuted();
        }

        bytes32 eip712Hash = getEIP712Hash(requestHash);
        if (!status.isPrevalidated) {
            verifySignature(maker, eip712Hash, signature);
        }

        requestStatus[requestHash].isExecuted = true;

        perSolverBalance[maker][solver] -= price;
        send(solver, price);

        emit RequestExecuted(requestHash);
    }

    // --- View methods ---

    function getRequestHash(
        Request memory request
    ) public view returns (bytes32 requestHash) {
        requestHash = keccak256(
            abi.encode(
                REQUEST_TYPEHASH,
                request.isCollectionRequest,
                request.maker,
                request.solver,
                request.token,
                request.tokenId,
                request.amount,
                request.price,
                request.recipient,
                request.chainId,
                request.deadline,
                request.salt
            )
        );
    }

    function getWithdrawHash(
        Withdraw calldata withdraw
    ) public view returns (bytes32 withdrawHash) {
        withdrawHash = keccak256(
            abi.encode(
                WITHDRAW_TYPEHASH,
                withdraw.solver,
                withdraw.user,
                withdraw.amount,
                withdraw.deadline,
                withdraw.salt
            )
        );
    }

    // --- Internal methods ---

    function send(address to, uint256 amount) internal {
        (bool result, ) = to.call{value: amount}("");
        if (!result) {
            revert UnsuccessfulCall();
        }
    }
}

