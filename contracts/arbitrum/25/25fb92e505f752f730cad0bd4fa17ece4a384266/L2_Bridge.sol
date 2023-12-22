// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./Bridge.sol";
import "./HopBridgeToken.sol";
import "./Lib_MerkleTree.sol";

interface I_L2_AmmWrapper {
    function attemptSwap(address recipient, uint256 amount, uint256 amountOutMin, uint256 deadline) external;
}

/**
 * @dev The L2_Bridge is responsible for aggregating pending Transfers into TransferRoots. Each newly
 * createdTransferRoot is then sent to the L1_Bridge. The L1_Bridge may be the TransferRoot's final
 * destination or the L1_Bridge may forward the TransferRoot to it's destination L2_Bridge.
 */

abstract contract L2_Bridge is Bridge {
    using SafeERC20 for IERC20;

    address public l1Governance;
    HopBridgeToken public immutable hToken;
    address public l1BridgeAddress;
    address public l1BridgeCaller;
    I_L2_AmmWrapper public ammWrapper;
    mapping(uint256 => bool) public activeChainIds;
    uint256 public minimumForceCommitDelay = 4 hours;
    uint256 public maxPendingTransfers = 512;
    uint256 public minBonderBps = 2;
    uint256 public minBonderFeeAbsolute = 0;

    mapping(uint256 => bytes32[]) public pendingTransferIdsForChainId;
    mapping(uint256 => uint256) public pendingAmountForChainId;
    mapping(uint256 => uint256) public lastCommitTimeForChainId;
    uint256 public transferNonceIncrementer;

    bytes32 private immutable NONCE_DOMAIN_SEPARATOR;

    event TransfersCommitted (
        uint256 indexed destinationChainId,
        bytes32 indexed rootHash,
        uint256 totalAmount,
        uint256 rootCommittedAt
    );

    event TransferSent (
        bytes32 indexed transferId,
        uint256 indexed chainId,
        address indexed recipient,
        uint256 amount,
        bytes32 transferNonce,
        uint256 bonderFee,
        uint256 index,
        uint256 amountOutMin,
        uint256 deadline
    );

    event TransferFromL1Completed (
        address indexed recipient,
        uint256 amount,
        uint256 amountOutMin,
        uint256 deadline,
        address indexed relayer,
        uint256 relayerFee
    );

    modifier onlyL1Bridge {
        _verifySender(l1BridgeCaller);
        _;
    }

    constructor (
        address _l1Governance,
        HopBridgeToken _hToken,
        address _l1BridgeAddress,
        uint256[] memory _activeChainIds,
        address[] memory bonders
    )
        public
        Bridge(bonders)
    {
        l1Governance = _l1Governance;
        hToken = _hToken;
        l1BridgeAddress = _l1BridgeAddress;

        for (uint256 i = 0; i < _activeChainIds.length; i++) {
            activeChainIds[_activeChainIds[i]] = true;
        }

        NONCE_DOMAIN_SEPARATOR = keccak256("L2_Bridge v1.0");
    }

    /* ========== Virtual functions ========== */

    function _sendCrossDomainMessage(bytes memory message) internal virtual;
    function _verifySender(address expectedSender) internal virtual;

    /* ========== Public/External functions ========== */

    /**
     * @notice _amount is the total amount the user wants to send including the Bonder fee
     * @dev Send  hTokens to another supported layer-2 or to layer-1 to be redeemed for the underlying asset.
     * @param chainId The chainId of the destination chain
     * @param recipient The address receiving funds at the destination
     * @param amount The amount being sent
     * @param bonderFee The amount distributed to the Bonder at the destination. This is subtracted from the `amount`.
     * @param amountOutMin The minimum amount received after attempting to swap in the destination
     * AMM market. 0 if no swap is intended.
     * @param deadline The deadline for swapping in the destination AMM market. 0 if no
     * swap is intended.
     */
    function send(
        uint256 chainId,
        address recipient,
        uint256 amount,
        uint256 bonderFee,
        uint256 amountOutMin,
        uint256 deadline
    )
        external
    {
        require(amount > 0, "L2_BRG: Must transfer a non-zero amount");
        require(amount >= bonderFee, "L2_BRG: Bonder fee cannot exceed amount");
        require(activeChainIds[chainId], "L2_BRG: chainId is not supported");
        uint256 minBonderFeeRelative = amount.mul(minBonderBps).div(10000);
        // Get the max of minBonderFeeRelative and minBonderFeeAbsolute
        uint256 minBonderFee = minBonderFeeRelative > minBonderFeeAbsolute ? minBonderFeeRelative : minBonderFeeAbsolute;
        require(bonderFee >= minBonderFee, "L2_BRG: bonderFee must meet minimum requirements");

        bytes32[] storage pendingTransfers = pendingTransferIdsForChainId[chainId];

        if (pendingTransfers.length >= maxPendingTransfers) {
            _commitTransfers(chainId);
        }

        hToken.burn(msg.sender, amount);

        bytes32 transferNonce = getNextTransferNonce();
        transferNonceIncrementer++;

        bytes32 transferId = getTransferId(
            chainId,
            recipient,
            amount,
            transferNonce,
            bonderFee,
            amountOutMin,
            deadline
        );
        uint256 transferIndex = pendingTransfers.length;
        pendingTransfers.push(transferId);

        pendingAmountForChainId[chainId] = pendingAmountForChainId[chainId].add(amount);

        emit TransferSent(
            transferId,
            chainId,
            recipient,
            amount,
            transferNonce,
            bonderFee,
            transferIndex,
            amountOutMin,
            deadline
        );
    }

    /**
     * @dev Aggregates all pending Transfers to the `destinationChainId` and sends them to the
     * L1_Bridge as a TransferRoot.
     * @param destinationChainId The chainId of the TransferRoot's destination chain
     */
    function commitTransfers(uint256 destinationChainId) external {
        uint256 minForceCommitTime = lastCommitTimeForChainId[destinationChainId].add(minimumForceCommitDelay);
        require(minForceCommitTime < block.timestamp || getIsBonder(msg.sender), "L2_BRG: Only Bonder can commit before min delay");
        lastCommitTimeForChainId[destinationChainId] = block.timestamp;

        _commitTransfers(destinationChainId);
    }

    /**
     * @dev Mints new hTokens for the recipient and optionally swaps them in the AMM market.
     * @param recipient The address receiving funds
     * @param amount The amount being distributed
     * @param amountOutMin The minimum amount received after attempting to swap in the destination
     * AMM market. 0 if no swap is intended.
     * @param deadline The deadline for swapping in the AMM market. 0 if no
     * swap is intended.
     * @param relayer The address of the relayer.
     * @param relayerFee The amount distributed to the relayer. This is subtracted from the `amount`.
     */
    function distribute(
        address recipient,
        uint256 amount,
        uint256 amountOutMin,
        uint256 deadline,
        address relayer,
        uint256 relayerFee
    )
        external
        onlyL1Bridge
        nonReentrant
    {
        _distribute(recipient, amount, amountOutMin, deadline, relayer, relayerFee);

        emit TransferFromL1Completed(
            recipient,
            amount,
            amountOutMin,
            deadline,
            relayer,
            relayerFee
        );
    }

    /**
     * @dev Allows the Bonder to bond an individual withdrawal and swap it in the AMM for the
     * canonical token on behalf of the user.
     * @param recipient The address receiving the Transfer
     * @param amount The amount being transferred including the `_bonderFee`
     * @param transferNonce Used to avoid transferId collisions
     * @param bonderFee The amount paid to the address that withdraws the Transfer
     * @param amountOutMin The minimum amount received after attempting to swap in the
     * AMM market. 0 if no swap is intended.
     * @param deadline The deadline for swapping in the AMM market. 0 if no
     * swap is intended.
     */
    function bondWithdrawalAndDistribute(
        address recipient,
        uint256 amount,
        bytes32 transferNonce,
        uint256 bonderFee,
        uint256 amountOutMin,
        uint256 deadline
    )
        external
        onlyBonder
        requirePositiveBalance
        nonReentrant
    {
        bytes32 transferId = getTransferId(
            getChainId(),
            recipient,
            amount,
            transferNonce,
            bonderFee,
            amountOutMin,
            deadline
        );

        _bondWithdrawal(transferId, amount);
        _markTransferSpent(transferId);
        _distribute(recipient, amount, amountOutMin, deadline, msg.sender, bonderFee);
    }

    /**
     * @dev Allows the L1 Bridge to set a TransferRoot
     * @param rootHash The Merkle root of the TransferRoot
     * @param totalAmount The total amount being transferred in the TransferRoot
     */
    function setTransferRoot(bytes32 rootHash, uint256 totalAmount) external onlyL1Bridge {
        _setTransferRoot(rootHash, totalAmount);
    }

    /* ========== Helper Functions ========== */

    function _commitTransfers(uint256 destinationChainId) internal {
        bytes32[] storage pendingTransfers = pendingTransferIdsForChainId[destinationChainId];
        require(pendingTransfers.length > 0, "L2_BRG: Must commit at least 1 Transfer");

        bytes32 rootHash = Lib_MerkleTree.getMerkleRoot(pendingTransfers);
        uint256 totalAmount = pendingAmountForChainId[destinationChainId];
        uint256 rootCommittedAt = block.timestamp;

        emit TransfersCommitted(destinationChainId, rootHash, totalAmount, rootCommittedAt);

        bytes memory confirmTransferRootMessage = abi.encodeWithSignature(
            "confirmTransferRoot(uint256,bytes32,uint256,uint256,uint256)",
            getChainId(),
            rootHash,
            destinationChainId,
            totalAmount,
            rootCommittedAt
        );

        pendingAmountForChainId[destinationChainId] = 0;
        delete pendingTransferIdsForChainId[destinationChainId];

        _sendCrossDomainMessage(confirmTransferRootMessage);
    }

    function _distribute(
        address recipient,
        uint256 amount,
        uint256 amountOutMin,
        uint256 deadline,
        address feeRecipient,
        uint256 fee
    )
        internal
    {
        if (fee > 0) {
            hToken.mint(feeRecipient, fee);
        }
        uint256 amountAfterFee = amount.sub(fee);

        if (
            (amountOutMin == 0 && deadline == 0) ||
            address(ammWrapper) == address(0)
        ) {
            hToken.mint(recipient, amountAfterFee);
        } else {
            hToken.mint(address(this), amountAfterFee);
            hToken.approve(address(ammWrapper), amountAfterFee);
            ammWrapper.attemptSwap(recipient, amountAfterFee, amountOutMin, deadline);
        }
    }

    /* ========== Override Functions ========== */

    function _transferFromBridge(address recipient, uint256 amount) internal override {
        hToken.mint(recipient, amount);
    }

    function _transferToBridge(address from, uint256 amount) internal override {
        hToken.burn(from, amount);
    }

    function _requireIsGovernance() internal override {
        _verifySender(l1Governance);
    }

    /* ========== External Config Management Functions ========== */

    function setL1Governance(address _l1Governance) external onlyGovernance {
        l1Governance = _l1Governance;
    }

    function setAmmWrapper(I_L2_AmmWrapper _ammWrapper) external onlyGovernance {
        ammWrapper = _ammWrapper;
    }

    function setL1BridgeAddress(address _l1BridgeAddress) external onlyGovernance {
        l1BridgeAddress = _l1BridgeAddress;
    }

    function setL1BridgeCaller(address _l1BridgeCaller) external onlyGovernance {
        l1BridgeCaller = _l1BridgeCaller;
    }

    function addActiveChainIds(uint256[] calldata chainIds) external onlyGovernance {
        for (uint256 i = 0; i < chainIds.length; i++) {
            activeChainIds[chainIds[i]] = true;
        }
    }

    function removeActiveChainIds(uint256[] calldata chainIds) external onlyGovernance {
        for (uint256 i = 0; i < chainIds.length; i++) {
            activeChainIds[chainIds[i]] = false;
        }
    }

    function setMinimumForceCommitDelay(uint256 _minimumForceCommitDelay) external onlyGovernance {
        minimumForceCommitDelay = _minimumForceCommitDelay;
    }

    function setMaxPendingTransfers(uint256 _maxPendingTransfers) external onlyGovernance {
        maxPendingTransfers = _maxPendingTransfers;
    }

    function setHopBridgeTokenOwner(address newOwner) external onlyGovernance {
        hToken.transferOwnership(newOwner);
    }

    function setMinimumBonderFeeRequirements(uint256 _minBonderBps, uint256 _minBonderFeeAbsolute) external onlyGovernance {
        require(_minBonderBps <= 10000, "L2_BRG: minBonderBps must not exceed 10000");
        minBonderBps = _minBonderBps;
        minBonderFeeAbsolute = _minBonderFeeAbsolute;
    }

    /* ========== Public Getters ========== */

    function getNextTransferNonce() public view returns (bytes32) {
        return keccak256(abi.encodePacked(NONCE_DOMAIN_SEPARATOR, getChainId(), transferNonceIncrementer));
    }
}

