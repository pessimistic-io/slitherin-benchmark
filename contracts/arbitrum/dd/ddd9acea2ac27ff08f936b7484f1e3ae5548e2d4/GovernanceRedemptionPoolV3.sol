// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IBurnableERC20} from "./IBurnableERC20.sol";
import {ITreasury} from "./ITreasury.sol";
import {NonblockingLzAppUpgradeable} from "./NonblockingLzAppUpgradeable.sol";

contract GovernanceRedemptionPoolV3 is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    NonblockingLzAppUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeERC20 for IBurnableERC20;

    struct Snapshot {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 lgoSupply;
        bool isFinalized;
    }

    struct SnapshotToken {
        address token;
        uint256 balance;
    }

    struct RedemptionRequest {
        address user;
        uint256 lgoAmount;
        uint256 timestamp;
    }

    /// @notice packet type will be sent through LayerZero
    uint16 public constant PT_REDEEM = 0;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    IBurnableERC20 public lgo;
    address public treasury;
    address[] public liquidTokens;
    uint256 public currentBatchId;
    uint256 public chainId;
    /// @notice list of all supported LayerZero chain ID
    uint16[] public lzRemoteChainIds;
    /// @notice map LayerZero chainID to evm chain ID
    mapping(uint16 l0ChainId => uint256 evmChainId) public mapRemoteChainIds;
    /// @notice snapshot info by batch
    mapping(uint256 batchId => Snapshot) public snapshots;
    /// @notice list of redeemable asset in each batch
    mapping(uint256 batchId => SnapshotToken[]) public snapshotTokens;
    /// @notice check if user is claimed or not
    mapping(uint256 batchId => mapping(address user => bool)) public isClaimed;
    /// @notice user redemption request sent in each batch
    mapping(uint256 batchId => RedemptionRequest[]) public redemptionRequests;
    /// @notice total LGO each user redeemed per batch on current chain
    mapping(uint256 batchId => mapping(address user => uint256 lgoAmount)) public userRedemption;
    /// @notice total LGO each user redeemed per batch on all chains
    mapping(uint256 batchId => mapping(address user => uint256 lgoAmount)) public userRedemptionAllChain;
    /// @notice total LGO redeemed by all user on each chain
    mapping(uint256 batchId => mapping(uint256 evmChainId => uint256 lgoAmount)) public totalRedemptionByChain;
    /// @notice total LGO redeemed by all user on all chains
    mapping(uint256 => uint256) public totalRedemptionAllChain;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _endpoint, address _lgo, address _treasury) external initializer {
        if (_endpoint == address(0)) revert ZeroAddress();
        if (_lgo == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __NonblockingLzAppUpgradeable_init(_endpoint);
        uint256 _chainId;
        assembly {
            _chainId := chainid()
        }
        chainId = _chainId;
        treasury = _treasury;
        lgo = IBurnableERC20(_lgo);
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    modifier onlyRedemptionActive() {
        if (!isRedemptionActive()) revert RedemptionNotActive();
        _;
    }

    // ============ VIEWS ==================

    function getSnapshotTokens(uint256 _batchId) external view returns (SnapshotToken[] memory _tokens) {
        _tokens = snapshotTokens[_batchId];
    }

    function getLiquidTokens() external view returns (address[] memory _tokens) {
        _tokens = liquidTokens;
    }

    /**
     * @notice calculate transaction fee to broadcast redemption message to all chains
     * @param _user address of user
     * @param _amount redeem amount
     * @return _nativeFee total chain native token fee
     * @return _zroFee total LayerZero fee if applicable, 0 for now
     * @return _fees native token fee charged by each chains
     */
    function estimateGasFee(address _user, uint256 _amount)
        public
        view
        returns (uint256 _nativeFee, uint256 _zroFee, uint256[] memory _fees)
    {
        bytes memory _payload = abi.encode(PT_REDEEM, abi.encodePacked(_user), _amount, currentBatchId, block.timestamp);
        uint256 _nChains = lzRemoteChainIds.length;
        _fees = new uint256[](_nChains);
        for (uint256 i = 0; i < _nChains;) {
            (uint256 _native, uint256 _zro) =
                lzEndpoint.estimateFees(lzRemoteChainIds[i], address(this), _payload, false, new bytes(0));
            _fees[i] = _native;
            _nativeFee += _native;
            _zroFee += _zro;

            unchecked {
                ++i;
            }
        }
    }

    function totalRedemptionRequests(uint256 _batchId) external view returns (uint256) {
        return redemptionRequests[_batchId].length;
    }

    function getRedemptionRequests(uint256 _batchId, uint256 _skip, uint256 _take)
        external
        view
        returns (RedemptionRequest[] memory requests, uint256 _totalRequests)
    {
        _totalRequests = redemptionRequests[_batchId].length;

        if (_skip < _totalRequests) {
            if ((_skip + _take) > _totalRequests) {
                _take = _totalRequests - _skip;
            }
            requests = new RedemptionRequest[](_take);
            for (uint256 i = 0; i < _take; i++) {
                RedemptionRequest memory _request = redemptionRequests[_batchId][_skip + i];
                requests[i] = _request;
            }
        }
    }

    function isRedemptionActive() public view returns (bool) {
        Snapshot memory _snapshot = snapshots[currentBatchId];
        return block.timestamp >= _snapshot.startTimestamp && block.timestamp < _snapshot.endTimestamp;
    }

    /**
     * @notice estimate returns amount when redeem an amount of LGO
     * @param _batchId batch ID, will return zero if batch snapshot not available
     * @param _lgoAmount amount of LGO user attempt to redeem
     */
    function redeemable(uint256 _batchId, uint256 _lgoAmount)
        public
        view
        returns (address[] memory _tokens, uint256[] memory _balances)
    {
        Snapshot memory _snapshot = snapshots[_batchId];
        SnapshotToken[] memory _snapshotTokens = snapshotTokens[_batchId];
        if (_snapshot.startTimestamp > 0) {
            _tokens = new address[](_snapshotTokens.length);
            _balances = new uint256[](_snapshotTokens.length);
            for (uint256 i = 0; i < _snapshotTokens.length; i++) {
                _tokens[i] = _snapshotTokens[i].token;
                _balances[i] = _lgoAmount * _snapshotTokens[i].balance / _snapshot.lgoSupply;
            }
        }
    }

    /**
     * @notice get actual claimable amount when batch is finalized
     * @param _batchId batch ID, will return zero if batch snapshot not finalized
     * @param _user address of user
     */
    function claimable(uint256 _batchId, address _user) public view returns (address[] memory, uint256[] memory) {
        Snapshot memory _snapshot = snapshots[_batchId];
        uint256 _lgoAmount = userRedemptionAllChain[_batchId][_user];
        if (_snapshot.isFinalized && _lgoAmount > 0 && !isClaimed[_batchId][_user]) {
            return redeemable(_batchId, _lgoAmount);
        }
    }

    // =============== MUTATIVE =================
    /**
     * @notice take an asset snapshot and start a new redemption batch.
     * @param _lgoSupply current LGO supply, agreed by all admin
     * @param _endTime redemption end time. After this time user can not redeem anymore, and admin can finalize the batch
     */
    function startNextBatch(uint256 _lgoSupply, uint256 _endTime) external onlyRole(CONTROLLER_ROLE) {
        if (isRedemptionActive()) revert RedemptionIsActive();
        if (_endTime < block.timestamp) revert InvalidEndTime();

        address[] memory _liquidTokens = liquidTokens;
        if (_liquidTokens.length == 0) revert NoRedemptionTokens();

        Snapshot memory _snapshot = Snapshot({
            startTimestamp: block.timestamp,
            endTimestamp: _endTime,
            lgoSupply: _lgoSupply,
            isFinalized: false
        });
        currentBatchId++;
        for (uint256 i = 0; i < _liquidTokens.length;) {
            address _token = _liquidTokens[i];
            snapshotTokens[currentBatchId].push(
                SnapshotToken({token: _token, balance: IERC20(_token).balanceOf(treasury)})
            );
            unchecked {
                ++i;
            }
        }

        snapshots[currentBatchId] = _snapshot;
        emit NextBatchStarted(currentBatchId, block.timestamp, _endTime, _lgoSupply);
    }

    /**
     * @notice lock an amount of LGO to redeem. Whenever the batch finalized, these LGO tokens will be burnt and the user can claim their assets
     * @param _amount LGO amount to lock
     */
    function redeem(uint256 _amount) external payable onlyRedemptionActive nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        (uint256 _nativeFee,, uint256[] memory _fees) = estimateGasFee(msg.sender, _amount);

        if (_nativeFee > msg.value) revert InsufficientNativeGasFee();
        address _sender = msg.sender;
        lgo.safeTransferFrom(_sender, address(this), _amount);
        redemptionRequests[currentBatchId].push(
            RedemptionRequest({user: _sender, lgoAmount: _amount, timestamp: block.timestamp})
        );
        userRedemption[currentBatchId][_sender] += _amount;
        userRedemptionAllChain[currentBatchId][_sender] += _amount;
        totalRedemptionByChain[currentBatchId][chainId] += _amount;
        totalRedemptionAllChain[currentBatchId] += _amount;
        emit Redeemed(currentBatchId, _sender, _amount);

        // send message crosschain
        bytes memory _payload =
            abi.encode(PT_REDEEM, abi.encodePacked(_sender), _amount, currentBatchId, block.timestamp);
        uint16[] memory _lzRemoteChainIds = lzRemoteChainIds;

        for (uint256 i = 0; i < _lzRemoteChainIds.length;) {
            _lzSend(_lzRemoteChainIds[i], _payload, payable(_sender), address(0), new bytes(0), _fees[i]);
            uint64 _nonce = lzEndpoint.getOutboundNonce(_lzRemoteChainIds[i], address(this));
            emit RedeemToChain(currentBatchId, _sender, _amount, _nonce, _lzRemoteChainIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice conclude the redemption batch, burn the locked LGO and request assets from treasury to return to user
     */
    function finalize(uint256 _batchId, uint256 _totalLgoRedeem) external onlyRole(CONTROLLER_ROLE) {
        Snapshot memory _snapshot = snapshots[_batchId];
        if (block.timestamp < _snapshot.endTimestamp) revert RedemptionNotEnded();
        if (_snapshot.isFinalized) revert BatchFinalized();
        if (_totalLgoRedeem != totalRedemptionAllChain[_batchId]) revert LGOAmountRedeemIncorrect();
        _snapshot.isFinalized = true;
        snapshots[_batchId] = _snapshot;
        lgo.burn(totalRedemptionByChain[_batchId][chainId]);
        (address[] memory _tokens, uint256[] memory _amounts) = redeemable(_batchId, _totalLgoRedeem);
        for (uint256 i = 0; i < _tokens.length;) {
            ITreasury(treasury).distribute(_tokens[i], address(this), _amounts[i]);
            unchecked {
                ++i;
            }
        }

        emit Finalized(_batchId, _totalLgoRedeem);
    }

    function claim(uint256 _batchId, address _to) external nonReentrant {
        address _sender = msg.sender;
        if (!isClaimed[_batchId][_sender]) {
            (address[] memory _tokens, uint256[] memory _balances) = claimable(_batchId, _sender);
            if (_tokens.length > 0) {
                isClaimed[_batchId][_sender] = true;
                for (uint256 i = 0; i < _tokens.length;) {
                    if (_balances[i] > 0) {
                        IERC20(_tokens[i]).safeTransfer(_to, _balances[i]);
                    }
                    unchecked {
                        ++i;
                    }
                }
                emit Claimed(_batchId, _sender, _to);
            }
        }
    }

    // =============== RESTRICTED ===============

    function addRemoteChain(uint16 _lzRemoteChainId, uint256 _evmChainId) external onlyRole(ADMIN_ROLE) {
        if (isRedemptionActive()) revert RedemptionIsActive();
        if (_evmChainId != chainId && mapRemoteChainIds[_lzRemoteChainId] == 0) {
            lzRemoteChainIds.push(_lzRemoteChainId);
            mapRemoteChainIds[_lzRemoteChainId] = _evmChainId;
            emit RemoteChainAdded(_lzRemoteChainId, _evmChainId);
        }
    }

    function removeRemoteChain(uint16 _lzRemoteChainId) external onlyRole(ADMIN_ROLE) {
        if (isRedemptionActive()) revert RedemptionIsActive();
        if (mapRemoteChainIds[_lzRemoteChainId] > 0) {
            delete mapRemoteChainIds[_lzRemoteChainId];
            uint256 _lzSize = lzRemoteChainIds.length;
            for (uint256 i = 0; i < _lzSize; i++) {
                if (lzRemoteChainIds[i] == _lzRemoteChainId) {
                    lzRemoteChainIds[i] = lzRemoteChainIds[_lzSize - 1];
                    lzRemoteChainIds.pop();
                    break;
                }
            }

            emit RemoteChainRemoved(_lzRemoteChainId);
        }
    }

    function updateLiquidTokens(address[] memory _tokens) external onlyRole(ADMIN_ROLE) {
        liquidTokens = _tokens;
        emit LiquidTokensUpdated();
    }

    /*=========================== INTERNALS ========================*/
    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload)
        internal
        override
    {
        uint16 _packetType;
        assembly {
            _packetType := mload(add(_payload, 32))
        }
        if (_packetType == PT_REDEEM) {
            (, bytes memory _user, uint256 _amount, uint256 _batchId, uint256 _requestTimestamp) =
                abi.decode(_payload, (uint16, bytes, uint256, uint256, uint256));
            address _userAddress;
            assembly {
                _userAddress := mload(add(_user, 20))
            }
            Snapshot memory _snapshot = snapshots[_batchId];
            if (_snapshot.startTimestamp == 0) revert BatchNotFound();
            if (_snapshot.isFinalized) revert BatchFinalized();
            uint256 _chainId = mapRemoteChainIds[_srcChainId];
            if (_chainId == 0) revert UnknownChainId();
            userRedemptionAllChain[_batchId][_userAddress] += _amount;
            totalRedemptionByChain[_batchId][_chainId] += _amount;
            totalRedemptionAllChain[_batchId] += _amount;
            emit RedeemFromChain(_srcChainId, _srcAddress, _nonce, _userAddress, _amount, _requestTimestamp, _batchId);
        } else {
            revert UnknownPacketType();
        }
    }

    // ============= EVENTS ==================
    event RedemptionStopped();
    event LiquidTokensUpdated();
    event NextBatchStarted(uint256 indexed _batchId, uint256 _startTime, uint256 _endTime, uint256 _lgoSupply);
    event Redeemed(uint256 _batchId, address _user, uint256 _amount);
    /// @notice emit when redeem message start broadcasting to all chains
    event RedeemToChain(uint256 _batchId, address _user, uint256 _amount, uint64 _nonce, uint16 _lzRemoteChainId);
    event Claimed(uint256 _batchId, address _user, address _to);
    event Finalized(uint256 _batchId, uint256 _totalLgoRedeem);
    event RemoteChainAdded(uint16 _lzRemoteChainId, uint256 _evmChainId);
    event RemoteChainRemoved(uint16 _lzRemoteChainId);
    /// @notice emit when redeem message from other chain received
    event RedeemFromChain(
        uint16 _srcChainId,
        bytes _srcAddress,
        uint64 _nonce,
        address _to,
        uint256 _amount,
        uint256 _requestTimestamp,
        uint256 _batchId
    );

    // ============== ERRORS ===================
    error UnknownPacketType();
    error ZeroAmount();
    error ZeroAddress();
    error InvalidEndTime();
    error RedemptionNotActive();
    error RedemptionIsActive();
    error RedemptionNotEnded();
    error BatchFinalized();
    error BatchNotFound();
    error NoRedemptionTokens();
    error LGOAmountRedeemIncorrect();
    error UnknownChainId();
    error InsufficientNativeGasFee();
}

