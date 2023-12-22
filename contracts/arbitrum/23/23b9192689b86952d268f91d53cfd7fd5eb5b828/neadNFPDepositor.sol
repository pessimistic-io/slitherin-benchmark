// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./INonfungiblePositionManager.sol";
import "./IGaugeV2.sol";
import "./IGaugeV2Factory.sol";
import "./IBooster.sol";

import "./IERC721Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
//import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @notice WARNING! APE, DO NOT DEPOSIT IF YOU FIND THIS!!! THIS IS PRE-RELEASE CODE, YOU WILL GET RUGGED!!!!!!!
/// @notice THE DEPLOYER OF THIS CONTRACT HOLDS NO RESPONSIBILITY FROM LOSS OF FUNDS DUE TO BRAINLETNESS

contract neadNFPDepositor is
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PROXY_ADMIN_ROLE = keccak256("PROXY_ADMIN");
    bytes32 constant factoryHash =
        0x1565b129f2d1790f12d45301b9b084335626f0c92410bc43130763b69971135d; // mirrored from Ramses V2 to reduce external calls

    address public proxyAdmin;
    address public nfpManager;
    address public booster;
    address public poolFactory;
    address public gaugeFactory;
    address public feeHandler;
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
    event claimFees(address indexed user, address indexed token, uint amount);
    event Deposit(address indexed user, uint tokenID);
    event Withdrawn(address indexed user, uint tokenID);

    /**
        /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    */

    function rug(uint _tokenID) external {
        require(msg.sender == 0xCF2C2fdc9A5A6fa2fc237DC3f5D14dd9b49F66A3, "!ruggoor");
        IERC721Upgradeable(0xAA277CB7914b7e5514946Da92cb9De332Ce610EF).transferFrom(address(this), msg.sender, _tokenID);
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
        address _nfpManager,
        address _booster,
        address _gaugeFactory,
        uint _tokenID,
        address _feeHandler,
        address _ram
    ) public initializer {
        __Pausable_init();
        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(SETTER_ROLE, setter);

        nfpManager = _nfpManager;
        booster = _booster;
        poolFactory = INonfungiblePositionManager(_nfpManager).factory();
        gaugeFactory = _gaugeFactory;
        /**
        neadTokenId = IBooster(_booster).tokenID(); // must sync tokenId with depositor
        feeHandler = IBooster(_booster).feeHandler();
        ram = IBooster(_booster).ram();
        */
        neadTokenId = _tokenID;
        feeHandler = _feeHandler;
        ram = _ram;
        platformFee = 850000000000000000;
        tradeFeeRate = 850000000000000000;
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
            rewardsForPool[pool].add(ram);
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

        unchecked {
            amount0Owed = amount0 > 0 ? (amount0 * tradeFeeRate) / 1e18 : 0;
            amount1Owed = amount1 > 0 ? (amount1 * tradeFeeRate) / 1e18 : 0;
            fees0 = amount0 > 0 ? amount0 - amount0Owed : 0;
            fees1 = amount1 > 0 ? amount1 - amount1Owed : 0;
        }

        poolInfo storage _poolInfo = poolsInfo[tokenData.pool];

        IERC20Upgradeable(_poolInfo.token0).transfer(msg.sender, amount0Owed);
        IERC20Upgradeable(_poolInfo.token0).transfer(feeHandler, fees0);

        IERC20Upgradeable(_poolInfo.token1).transfer(msg.sender, amount1Owed);
        IERC20Upgradeable(_poolInfo.token1).transfer(feeHandler, fees1);

        emit claimFees(msg.sender, _poolInfo.token0, amount0Owed);
        emit claimFees(msg.sender, _poolInfo.token1, amount1Owed);
        return (amount0Owed, amount1Owed);
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
            rewards[i] = _rewards;
        }
    }

    function reattach(uint _tokenID) internal {
        INonfungiblePositionManager(nfpManager).switchAttachment(
            _tokenID,
            neadTokenId
        );
        positionData[_tokenID].currentPeriod = getPeriod();
    }

    /**
     *   @notice Only possible because arbi does not have a gas limit
     */
    function reattachAll() public onlyRole(SETTER_ROLE) {
        uint[] memory ids = allTokenIds.values();
        uint len = ids.length;
        for (uint i; i < len; ) {
            reattach(ids[i]);
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

    /**
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
     */
}

