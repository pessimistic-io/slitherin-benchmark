// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./INonfungiblePositionManager.sol";
import "./IGaugeV2.sol";
import "./IGaugeV2Factory.sol";
import "./IBooster.sol";
import "./ISwappoor.sol";
import "./IVeDepositor.sol";
import "./IFeeHandler.sol";
import "./INeadTradeFeeHandler.sol";

import "./IERC721Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./UUPSUpgradeable.sol";

contract neadNFPDepositor is
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PROXY_ADMIN_ROLE = keccak256("PROXY_ADMIN");
    bytes32 constant factoryHash =
        0x1565b129f2d1790f12d45301b9b084335626f0c92410bc43130763b69971135d; // mirrored from Ramses V2 to reduce external calls

    address public proxyAdmin;
    address public nfpManager;
    address public booster;
    address public poolFactory;
    address public gaugeFactory;
    address public feeHandler;
    address public tradeFeeReceiver;
    address public swappoor;
    address neadRam;
    address ram;

    // Mirrored from booster
    uint public neadTokenId;
    uint public platformFee;
    uint public tradeFeeRate;

    struct PositionInfo {
        address owner;
        address pool;
        address gauge;
        uint currentPeriod;
    }
    // tokenId -> data
    mapping(uint => PositionInfo) public positionData;
    // user -> tokenId's
    mapping(address => EnumerableSetUpgradeable.UintSet) userTokenIds;
    // set of all tokenId's deposited
    EnumerableSetUpgradeable.UintSet allTokenIds;
    // pool -> reward tokens
    mapping(address => EnumerableSetUpgradeable.AddressSet) rewardsForPool;
    // token0 -> token1 -> fee -> pool address
    mapping(address => mapping(address => mapping(uint24 => address))) pools;

    struct poolInfo {
        address token0;
        address token1;
        uint24 fee;
    }
    mapping(address => poolInfo) poolsInfo;
    // pool -> gauge
    mapping(address => address) gaugeForPool;

    event claimReward(
        address indexed user,
        address indexed reward,
        uint amount
    );
    event claimFees(
        address indexed user,
        address indexed token0,
        address indexed token1,
        uint amount0,
        uint amount1
    );
    event Deposit(address indexed user, uint tokenID);
    event Withdrawn(address indexed user, uint tokenID);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     *
     * @param _nfpManager Ramses NFPPositionsManager contract
     * @param _booster Ennead Depositor contract
     * @param _gaugeFactory Ramses V2 gauge factory
     */
    function initialize(
        address admin,
        address pauser,
        address setter,
        address operator,
        address _nfpManager,
        address _booster,
        address _gaugeFactory,
        address _swappoor,
        address _proxyAdmin
    ) public initializer {
        __Pausable_init();
        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(SETTER_ROLE, setter);
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(PROXY_ADMIN_ROLE, _proxyAdmin);
        _setRoleAdmin(PROXY_ADMIN_ROLE, PROXY_ADMIN_ROLE);
        proxyAdmin = _proxyAdmin;

        nfpManager = _nfpManager;
        booster = _booster;
        poolFactory = INonfungiblePositionManager(_nfpManager).factory();
        gaugeFactory = _gaugeFactory;
        neadTokenId = IBooster(_booster).tokenID(); // must sync tokenId with depositor
        feeHandler = IBooster(_booster).feeHandler();
        ram = IBooster(_booster).ram();
        swappoor = _swappoor;
        IERC20Upgradeable(ram).approve(_swappoor, type(uint).max);
        neadRam = IBooster(booster).neadRam();
    }

    function setFeeReceivers(
        address _feeHandler,
        address _tradeFeeReceiver
    ) external onlyRole(SETTER_ROLE) {
        if (_feeHandler != address(0)) {
            feeHandler = _feeHandler;
        }

        if (_tradeFeeReceiver != address(0)) {
            tradeFeeReceiver = _tradeFeeReceiver;
        }
    }

    function getPeriod() public view returns (uint) {
        return (block.timestamp / 1 weeks) * 1 weeks;
    }

    function onERC721Received(
        address,
        address _from,
        uint256 _tokenID,
        bytes calldata
    ) external whenNotPaused returns (bytes4) {
        require(msg.sender == nfpManager, "Can only receive Ramses NFP's");
        require(_tokenID > 0, "Cannot receive zero tokenID");

        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(nfpManager).positions(_tokenID);
        address pool = pools[token0][token1][fee];
        address gauge = gaugeForPool[pool];
        if (pool == address(0)) {
            pool = computePoolAddress(
                poolInfo({token0: token0, token1: token1, fee: fee})
            );
            gauge = IGaugeFactory(gaugeFactory).getGauge(pool);
            pools[token0][token1][fee] = pool;
            poolsInfo[pool] = poolInfo({
                token0: token0,
                token1: token1,
                fee: fee
            });
            gaugeForPool[pool] = gauge;
            address[] memory _rewards = IGaugeV2(gauge).getRewardTokens();
            uint len = _rewards.length;
            for (uint i; i < len; ) {
                rewardsForPool[pool].add(_rewards[i]);
                unchecked {
                    ++i;
                }
            }
        }

        positionData[_tokenID] = PositionInfo({
            owner: _from,
            pool: pool,
            gauge: gauge,
            currentPeriod: getPeriod()
        });
        userTokenIds[_from].add(_tokenID);
        allTokenIds.add(_tokenID);
        INonfungiblePositionManager(nfpManager).switchAttachment(
            _tokenID,
            neadTokenId
        );

        emit Deposit(_from, _tokenID);
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function withdraw(uint _tokenID) external whenNotPaused {
        PositionInfo storage tokenData = positionData[_tokenID];
        require(msg.sender == tokenData.owner);
        getReward(_tokenID);
        collectFees(_tokenID);
        INonfungiblePositionManager(nfpManager).switchAttachment(_tokenID, 0);
        IERC721Upgradeable(nfpManager).safeTransferFrom(
            address(this),
            msg.sender,
            _tokenID
        );

        delete positionData[_tokenID];
        userTokenIds[msg.sender].remove(_tokenID);
        allTokenIds.remove(_tokenID);
        emit Withdrawn(msg.sender, _tokenID);
    }

    function getReward(uint _tokenID) public {
        PositionInfo storage tokenData = positionData[_tokenID];
        require(msg.sender == tokenData.owner);

        address[] memory tokens = rewardsForPool[tokenData.pool].values();
        IGaugeV2(tokenData.gauge).getReward(_tokenID, tokens);
        // contract does not hold tokens so no need to get delta
        for (uint i; i < tokens.length; ) {
            IERC20Upgradeable _token = IERC20Upgradeable(tokens[i]);
            uint bal = _token.balanceOf(address(this));

            if (bal > 0) {
                uint owed;

                unchecked {
                    owed = (bal * platformFee) / 1e18;
                }

                _token.transfer(msg.sender, owed);
                _token.transfer(feeHandler, bal - owed);
                IFeeHandler(feeHandler).notifyFees(tokens[i], bal - owed);
                emit claimReward(msg.sender, tokens[i], owed);
            }

            unchecked {
                ++i;
            }
        }

        if (getPeriod() > tokenData.currentPeriod) {
            reattach(_tokenID);
        }
    }

    function getAllRewards() external {
        uint[] memory _tokenIDs = userTokenIds[msg.sender].values();
        uint len = _tokenIDs.length;

        for (uint i; i < len; ) {
            getReward(_tokenIDs[i]);
            unchecked {
                ++i;
            }
        }
    }

    function collectFees(uint _tokenID) public returns (uint, uint) {
        PositionInfo storage tokenData = positionData[_tokenID];
        require(msg.sender == tokenData.owner);

        (uint amount0, uint amount1) = INonfungiblePositionManager(nfpManager)
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: _tokenID,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

        uint amount0Owed;
        uint amount1Owed;
        uint fees0;
        uint fees1;

        poolInfo storage _poolInfo = poolsInfo[tokenData.pool];

        unchecked {
            if (amount0 > 0) {
                amount0Owed = (amount0 * tradeFeeRate) / 1e18;
                fees0 = amount0 - amount0Owed;
                IERC20Upgradeable(_poolInfo.token0).transfer(
                    msg.sender,
                    amount0Owed
                );
                IERC20Upgradeable(_poolInfo.token0).transfer(
                    tradeFeeReceiver,
                    fees0
                );
                INeadTradeFeeHandler(tradeFeeReceiver).notifyTokens(_poolInfo.token0);
            }

            if (amount1 > 0) {
                amount1Owed = (amount1 * tradeFeeRate) / 1e18;
                fees1 = amount1 - amount1Owed;
                IERC20Upgradeable(_poolInfo.token1).transfer(
                    msg.sender,
                    amount1Owed
                );
                IERC20Upgradeable(_poolInfo.token1).transfer(
                    tradeFeeReceiver,
                    fees1
                );
                INeadTradeFeeHandler(tradeFeeReceiver).notifyTokens(_poolInfo.token1);
            }
        }

        emit claimFees(
            msg.sender,
            _poolInfo.token0,
            _poolInfo.token1,
            amount0Owed,
            amount1Owed
        );
        return (amount0Owed, amount1Owed);
    }

    function collectAllFees() external {
        uint[] memory _tokenIDs = userTokenIds[msg.sender].values();
        uint len = _tokenIDs.length;

        for (uint i; i < len; ) {
            collectFees(_tokenIDs[i]);
            unchecked {
                ++i;
            }
        }
    }

    function earned(
        uint _tokenID
    ) external view returns (uint[] memory rewards) {
        PositionInfo storage tokenData = positionData[_tokenID];

        address[] memory tokens = rewardsForPool[tokenData.pool].values();
        IGaugeV2 gauge = IGaugeV2(gaugeForPool[tokenData.pool]);
        uint len = tokens.length;
        rewards = new uint[](len);
        uint _rewards;
        uint fee;

        for (uint i; i < len; ++i) {
            _rewards = gauge.earned(tokens[i], _tokenID);
            fee = (_rewards * platformFee) / 1e18;
            rewards[i] = fee;
        }
    }

    function reattach(uint _tokenID) public {
        try
            INonfungiblePositionManager(nfpManager).switchAttachment(
                _tokenID,
                neadTokenId
            )
        {
            positionData[_tokenID].currentPeriod = getPeriod();
        } catch {}
    }

    function batchReattach(uint[] calldata tokenIDs) external {
        for (uint i; i < tokenIDs.length; ) {
            reattach(tokenIDs[i]);
            unchecked {
                ++i;
            }
        }
    }

    function getAllTokenIds() external view returns (uint[] memory tokenIDs) {
        tokenIDs = allTokenIds.values();
    }

    function allTokenIdsLength() external view returns (uint len) {
        len = allTokenIds.length();
    }

    function alltokenIdsPerUser(
        address user
    ) external view returns (uint[] memory tokenIDs) {
        tokenIDs = userTokenIds[user].values();
    }

    function userTokenIdsLength(address user) external view returns (uint len) {
        len = userTokenIds[user].length();
    }

    function syncRewardsList(address pool) public onlyRole(SETTER_ROLE) {
        address gauge = gaugeForPool[pool];
        if (gauge == address(0)) return;
        address[] memory _rewards = IGaugeV2(gauge).getRewardTokens();
        uint len = _rewards.length;

        for (uint i; i < len; ) {
            rewardsForPool[pool].add(_rewards[i]); // If already in pool it won't be added again
            unchecked {
                ++i;
            }
        }
    }

    function batchSyncRewardsList(address[] calldata _pools) external {
        for (uint i; i < _pools.length; ) {
            syncRewardsList(_pools[i]);
            unchecked {
                ++i;
            }
        }
    }

    function addRewardsPerPool(
        address pool,
        address reward
    ) external onlyRole(SETTER_ROLE) {
        rewardsForPool[pool].add(reward);
    }

    function removeRewardForPool(
        address pool,
        address reward
    ) external onlyRole(SETTER_ROLE) {
        rewardsForPool[pool].remove(reward);
    }

    function rewardsList(
        address pool
    ) external view returns (address[] memory rewards) {
        rewards = rewardsForPool[pool].values();
    }

    /**
     *   @notice recovers nfp's that weren't transferred using safeTransferFrom()
     */
    function recoverNFP(uint _tokenID) external onlyRole(SETTER_ROLE) {
        require(!allTokenIds.contains(_tokenID), "Properly attached!");
        IERC721Upgradeable(nfpManager).safeTransferFrom(
            address(this),
            msg.sender,
            _tokenID,
            "0x"
        );
    }

    function syncFeeRate() external {
        platformFee = 1e18 - IBooster(booster).platformFee();
    }

    /// @dev 0.85 * 10**18 for a 15% fee
    function setTradeFeeRate(
        uint _tradeFeeRate
    ) external onlyRole(SETTER_ROLE) {
        tradeFeeRate = _tradeFeeRate;
    }

    function computePoolAddress(
        poolInfo memory info
    ) internal view returns (address pool) {
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            poolFactory,
                            keccak256(
                                abi.encode(info.token0, info.token1, info.fee)
                            ),
                            factoryHash
                        )
                    )
                )
            )
        );
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(PROXY_ADMIN_ROLE) {}

    /// @dev grantRole already checks role, so no more additional checks are necessary
    function changeAdmin(address newAdmin) external {
        grantRole(PROXY_ADMIN_ROLE, newAdmin);
        renounceRole(PROXY_ADMIN_ROLE, proxyAdmin);
        proxyAdmin = newAdmin;
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}

