// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./ERC165Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IClusterRewards.sol";
import "./IClusterRegistry.sol";


contract RewardDelegators is
    Initializable,  // initializer
    ContextUpgradeable,  // _msgSender, _msgData
    ERC165Upgradeable,  // supportsInterface
    AccessControlUpgradeable,  // RBAC
    AccessControlEnumerableUpgradeable,  // RBAC enumeration
    ERC1967UpgradeUpgradeable,  // delegate slots, proxy admin, private upgrade
    UUPSUpgradeable  // public upgrade
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    // initializes the logic contract without any admins
    // safeguard against takeover of the logic contract
    constructor() initializer {}

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()));
        _;
    }

//-------------------------------- Overrides start --------------------------------//

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable, AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _grantRole(bytes32 role, address account) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._grantRole(role, account);
    }

    function _revokeRole(bytes32 role, address account) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._revokeRole(role, account);

        // protect against accidentally removing all admins
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0);
    }

    function _authorizeUpgrade(address /*account*/) onlyAdmin internal view override {}

//-------------------------------- Overrides end --------------------------------//

//-------------------------------- Initializer start --------------------------------//

    uint256[50] private __gap1;

    function initialize(
        address _stakeAddress,
        address _clusterRewardsAddress,
        address _clusterRegistry,
        address _PONDAddress,
        bytes32[] memory _tokenIds,
        uint256[] memory _rewardFactors
    )
        initializer
        public
    {
        require(
            _tokenIds.length == _rewardFactors.length,
            "RD:I-Each TokenId should have a corresponding Reward Factor and vice versa"
        );

        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlEnumerable_init_unchained();
        __ERC1967Upgrade_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        stakeAddress = _stakeAddress;
        emit StakeAddressUpdated(_stakeAddress);

        clusterRegistry = IClusterRegistry(_clusterRegistry);
        emit ClusterRegistryUpdated(_clusterRegistry);

        clusterRewards = IClusterRewards(_clusterRewardsAddress);
        emit ClusterRewardsAddressUpdated(_clusterRewardsAddress);

        PONDToken = IERC20Upgradeable(_PONDAddress);
        emit PONDAddressUpdated(_PONDAddress);

        for(uint256 i=0; i < _tokenIds.length; i++) {
            rewardFactor[_tokenIds[i]] = _rewardFactors[i];
            tokenIndex[_tokenIds[i]] = tokenList.length;
            tokenList.push(_tokenIds[i]);
            emit AddReward(_tokenIds[i], _rewardFactors[i]);
        }
    }

//-------------------------------- Initializer end --------------------------------//


    struct Cluster {
        mapping(bytes32 => uint256) totalDelegations;
        mapping(address => mapping(bytes32 => uint256)) delegators;
        mapping(address => mapping(bytes32 => uint256)) rewardDebt;
        mapping(bytes32 => uint256) accRewardPerShare;
    }

    mapping(address => Cluster) clusters;

    address public stakeAddress;
    mapping(bytes32 => uint256) public rewardFactor;
    mapping(bytes32 => uint256) public tokenIndex;
    bytes32[] public tokenList;
    IClusterRewards public clusterRewards;
    IClusterRegistry public clusterRegistry;
    IERC20Upgradeable public PONDToken;

    event AddReward(bytes32 tokenId, uint256 rewardFactor);
    event RemoveReward(bytes32 tokenId);
    event RewardsUpdated(bytes32 tokenId, uint256 rewardFactor);
    event ClusterRewardDistributed(address cluster);
    event RewardsWithdrawn(address cluster, address delegator, bytes32[] tokenIds, uint256 rewards);
    event StakeAddressUpdated(address _updatedStakeAddress);
    event ClusterRewardsAddressUpdated(address _updatedClusterRewards);
    event ClusterRegistryUpdated(address _updatedClusterRegistry);
    event PONDAddressUpdated(address _updatedPOND);

    modifier onlyStake() {
        require(_msgSender() == stakeAddress, "RD:OS-only stake contract can invoke");
        _;
    }

    function addRewardFactor(bytes32 _tokenId, uint256 _rewardFactor) external onlyAdmin {
        require(rewardFactor[_tokenId] == 0, "RD:AR-Reward already exists");
        require(_rewardFactor != 0, "RD:AR-Reward cant be 0");
        rewardFactor[_tokenId] = _rewardFactor;
        tokenIndex[_tokenId] = tokenList.length;
        tokenList.push(_tokenId);
        emit AddReward(_tokenId, _rewardFactor);
    }

    function removeRewardFactor(bytes32 _tokenId) external onlyAdmin {
        require(rewardFactor[_tokenId] != 0, "RD:RR-Reward doesnt exist");
        bytes32 tokenToReplace = tokenList[tokenList.length - 1];
        uint256 originalTokenIndex = tokenIndex[_tokenId];
        tokenList[originalTokenIndex] = tokenToReplace;
        tokenIndex[tokenToReplace] = originalTokenIndex;
        tokenList.pop();
        delete rewardFactor[_tokenId];
        delete tokenIndex[_tokenId];
        emit RemoveReward(_tokenId);
    }

    function updateRewardFactor(bytes32 _tokenId, uint256 _updatedRewardFactor) external onlyAdmin {
        require(rewardFactor[_tokenId] != 0, "RD:UR-Cant update reward that doesnt exist");
        require(_updatedRewardFactor != 0, "RD:UR-Reward cant be 0");
        rewardFactor[_tokenId] = _updatedRewardFactor;
        emit RewardsUpdated(_tokenId, _updatedRewardFactor);
    }

    function _updateRewards(address _cluster) public {
        uint256 reward = clusterRewards.claimReward(_cluster);
        if(reward == 0) {
            return;
        }

        (uint256 _commission, address _rewardAddress) = clusterRegistry.getRewardInfo(_cluster);

        uint256 commissionReward = (reward * _commission) / 100;
        uint256 delegatorReward = reward - commissionReward;
        bytes32[] memory tokens = tokenList;
        uint256[] memory delegations = new uint256[](tokens.length);
        uint256 delegatedTokens = 0;
        for(uint i=0; i < tokens.length; i++) {
            delegations[i] = clusters[_cluster].totalDelegations[tokens[i]];
            if(delegations[i] != 0) {
                delegatedTokens++;
            }
        }
        for(uint i=0; i < tokens.length; i++) {
            // clusters[_cluster].accRewardPerShare[tokens[i]] = clusters[_cluster].accRewardPerShare[tokens[i]].add(
            //                                                         delegatorReward
            //                                                         .mul(rewardFactor[tokens[i]])
            //                                                         .mul(10**30)
            //                                                         .div(weightedStake)
            //                                                     );
            if(delegations[i] != 0) {
                clusters[_cluster].accRewardPerShare[tokens[i]] = clusters[_cluster].accRewardPerShare[tokens[i]] +
                                                                   (((delegatorReward * (10**30)) / delegatedTokens) / delegations[i]);

            }
        }
        if(commissionReward != 0) {
            transferRewards(_rewardAddress, commissionReward);
        }
        emit ClusterRewardDistributed(_cluster);
    }

    function delegate(
        address _delegator,
        address _cluster,
        bytes32[] memory _tokens,
        uint256[] memory _amounts
    ) public onlyStake {
        _updateTokens(_delegator, _cluster, _tokens, _amounts, true);
    }

    function _updateTokens(
        address _delegator,
        address _cluster,
        bytes32[] memory _tokens,
        uint256[] memory _amounts,
        bool _isDelegation
    ) internal returns(uint256 _aggregateReward) {
        _updateRewards(_cluster);

        for(uint256 i = 0; i < _tokens.length; i++) {
            bytes32 _tokenId = _tokens[i];
            uint256 _amount = _amounts[i];

            (uint256 _oldBalance, uint256 _newBalance) = _updateBalances(
                _cluster,
                _delegator,
                _tokenId,
                _amount,
                _isDelegation
            );

            uint256 _reward = _updateDelegatorRewards(
                _cluster,
                _delegator,
                _tokenId,
                _oldBalance,
                _newBalance
            );

            _aggregateReward = _aggregateReward + _reward;
        }

        if(_aggregateReward != 0) {
            transferRewards(_delegator, _aggregateReward);
            emit RewardsWithdrawn(_cluster, _delegator, _tokens, _aggregateReward);
        }
    }

    function _updateBalances(
        address _cluster,
        address _delegator,
        bytes32 _tokenId,
        uint256 _amount,
        bool _isDelegation
    ) internal returns(uint256 _oldBalance, uint256 _newBalance) {
        _oldBalance = clusters[_cluster].delegators[_delegator][_tokenId];

        // short circuit
        if(_amount == 0) {
            _newBalance = _oldBalance;
            return (_oldBalance, _newBalance);
        }

        // update balances
        if(_isDelegation) {
            _newBalance =  _oldBalance + _amount;
            clusters[_cluster].totalDelegations[_tokenId] = clusters[_cluster].totalDelegations[_tokenId]
                                                             + _amount;
        } else {
            _newBalance =  _oldBalance - _amount;
            clusters[_cluster].totalDelegations[_tokenId] = clusters[_cluster].totalDelegations[_tokenId]
                                                             - _amount;
        }
        clusters[_cluster].delegators[_delegator][_tokenId] = _newBalance;
    }

    function _updateDelegatorRewards(
        address _cluster,
        address _delegator,
        bytes32 _tokenId,
        uint256 _oldBalance,
        uint256 _newBalance
    ) internal returns(uint256 _reward) {
        uint256 _accRewardPerShare = clusters[_cluster].accRewardPerShare[_tokenId];
        uint256 _rewardDebt = clusters[_cluster].rewardDebt[_delegator][_tokenId];

        // pending rewards
        uint256 _tokenPendingRewards = (_accRewardPerShare * _oldBalance) / (10**30);

        // calculating pending rewards for the delegator if any
        _reward = _tokenPendingRewards - _rewardDebt;

        // short circuit
        if(_oldBalance == _newBalance && _reward == 0) {
            return _reward;
        }

        // update the debt for next reward calculation
        clusters[_cluster].rewardDebt[_delegator][_tokenId] = (_accRewardPerShare * _newBalance) / (10**30);
    }

    function undelegate(
        address _delegator,
        address _cluster,
        bytes32[] memory _tokens,
        uint256[] memory _amounts
    ) public onlyStake {
        _updateTokens(_delegator, _cluster, _tokens, _amounts, false);
    }

    function withdrawRewards(address _delegator, address _cluster) public returns(uint256) {
        return _updateTokens(_delegator, _cluster, tokenList, new uint256[](tokenList.length), true);
    }

    function withdrawRewards(address _delegator, address[] calldata _clusters) external {
        for(uint256 i=0; i < _clusters.length; i++) {
            withdrawRewards(_delegator, _clusters[i]);
        }
    }

    function transferRewards(address _to, uint256 _amount) internal {
        PONDToken.transfer(_to, _amount);
    }

    function getClusterDelegation(address _cluster, bytes32 _tokenId)
        external
        view
        returns(uint256)
    {
        return clusters[_cluster].totalDelegations[_tokenId];
    }

    function getDelegation(address _cluster, address _delegator, bytes32 _tokenId)
        external
        view
        returns(uint256)
    {
        return clusters[_cluster].delegators[_delegator][_tokenId];
    }

    function updateStakeAddress(address _updatedStakeAddress) external onlyAdmin {
        require(
            _updatedStakeAddress != address(0),
            "RD:USA-Stake contract address cant be 0"
        );
        stakeAddress = _updatedStakeAddress;
        emit StakeAddressUpdated(_updatedStakeAddress);
    }

    function updateClusterRewards(
        address _updatedClusterRewards
    ) external onlyAdmin {
        require(
            _updatedClusterRewards != address(0),
            "RD:UCR-ClusterRewards address cant be 0"
        );
        clusterRewards = IClusterRewards(_updatedClusterRewards);
        emit ClusterRewardsAddressUpdated(_updatedClusterRewards);
    }

    function updateClusterRegistry(
        address _updatedClusterRegistry
    ) external onlyAdmin {
        require(
            _updatedClusterRegistry != address(0),
            "RD:UCR-Cluster Registry address cant be 0"
        );
        clusterRegistry = IClusterRegistry(_updatedClusterRegistry);
        emit ClusterRegistryUpdated(_updatedClusterRegistry);
    }

    function updatePONDAddress(address _updatedPOND) external onlyAdmin {
        require(
            _updatedPOND != address(0),
            "RD:UPA-Updated POND token address cant be 0"
        );
        PONDToken = IERC20Upgradeable(_updatedPOND);
        emit PONDAddressUpdated(_updatedPOND);
    }

    function getAccRewardPerShare(address _cluster, bytes32 _tokenId) external view returns(uint256) {
        return clusters[_cluster].accRewardPerShare[_tokenId];
    }

    function applyDiffs(
        address[] calldata _delegators,
        address[] calldata _clusters,
        bytes32[] calldata _tokens,
        uint256[] calldata _allAmounts,
        bool[] calldata _isDelegations
    ) external onlyAdmin {
        require(_delegators.length == _clusters.length);
        require(_delegators.length * _tokens.length == _allAmounts.length);
        require(_delegators.length == _isDelegations.length);

        for(uint256 _idx = 0; _idx < _delegators.length; _idx++) {
            address _delegator = _delegators[_idx];
            address _cluster = _clusters[_idx];
            uint256[] memory _amounts = _allAmounts[(_idx*_tokens.length):((_idx+1)*_tokens.length)];
            bool _isDelegation = _isDelegations[_idx];

            for(uint256 _tidx = 0; _tidx < _tokens.length; _tidx++) {
                _updateBalances(_cluster, _delegator, _tokens[_tidx], _amounts[_tidx], _isDelegation);
            }
        }
    }
}

