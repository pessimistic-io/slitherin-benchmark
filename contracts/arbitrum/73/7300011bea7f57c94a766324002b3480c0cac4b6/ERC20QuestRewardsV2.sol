// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./CurrencyTransferLib.sol";

import "./IERC20.sol";
import "./Address.sol";
import "./ECDSA.sol";

import "./draft-EIP712Upgradeable.sol";
import "./Initializable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ERC2771ContextUpgradeable.sol";


contract ERC20QuestRewardsStorage {
    /* ============ TypeHashes and Constants ============ */
    
    bytes32 public constant ERC20_ACTIVATE_CAMPAIGN_TYPEHASH = keccak256(
        "ERC20LaunchCampaign(uint96 cid,address admin,uint256 startTime,uint256 claimTime,CampaignReward[] campaignRewards)CampaignReward(uint96 rewardId,address tokenAddress,uint256 numRewards)"
    );

    bytes32 public constant ERC20_CLAIM_TYPEHASH = keccak256(
        "ERC20Claim(uint96 rewardId,uint96 userId,address userAddress,uint256 amountToClaim)"
    );

    bytes32 public constant ERC20_DUMMY_CLAIM_TYPEHASH = keccak256(
        "ERC20DummyClaim(uint96 cid,uint96 rewardId,uint96 userId,address userAddress)"
    );

    bytes32 public constant ERC20_REWARD_CONFIG_TYPEHASH = keccak256(
        "CampaignReward(uint96 rewardId,address tokenAddress,uint256 numRewards)"
    );

    /* ============ Events ============ */

    event ERC20SignerUpdate(address oldSigner, address newSigner);
    event ERC20ClaimTimeUpdate(uint96 indexed cid, uint256 oldClaimTime, uint256 newClaimTime);

    event ERC20LaunchCampaign(
        uint96 indexed cid,
        address admin,
        uint256 startTime,
        uint256 claimTime,
        CampaignReward[] campaignRewards
    );

    event ERC20Claim(
        uint96 indexed rewardId,
        uint96 indexed userId,
        address indexed userAddress,
        uint256 amountToClaim
    );

    event ERC20DummyClaim(
        uint96 indexed cid,
        uint96 indexed rewardId,
        uint96 indexed userId,
        address userAddress
    );

    event ERC20Withdraw(
        uint96 indexed cid, 
        uint96 indexed rewardId,
        address indexed tokenAddress,
        address admin,
        uint256 amount
    );
    
    /* ============ Structs ============ */

    // Input when activating a campaign
    struct CampaignReward {
        uint96 rewardId; // reward id
        address tokenAddress; // token address
        uint256 numRewards; // number of reward tokens
    }

    struct CampaignConfig {
        address admin; // campaign admin, only admin can withdraw
        uint256 startTime; // campaign start time
        uint256 claimTime; // campaign claim time
    }

    struct RewardConfig {
        uint96 cid; // campaign id
        address tokenAddress; // token address
        uint256 numRewards; // number of reward tokens
        uint256 tokensClaimed; // number of tokens claimed
        uint256 usersClaimed; // total number of addresses who claimed
    }

    /* ============ State Variables ============ */

    // Intract Signer
    address public intractSigner;

    // cid => Campaign configuration
    mapping(uint96 => CampaignConfig) public campaignConfigs;

    // cid => array of rewardIds
    // used only when admin wants to withdraw
    mapping(uint96 => uint96[]) public campaignToRewards;

    // rewardId => Reward configuration
    mapping(uint96 => RewardConfig) public rewardConfigs;

    // rewardId => userAddress => if he has claimed
    mapping(uint96 => mapping(address => bool)) public hasClaimed;

    // rewardId => userId => if he has claimed
    mapping(uint96 => mapping(uint96 => bool)) public hasClaimedUserId;

    // signature => if it has been used
    mapping(bytes32 => bool) public usedDummyClaimHashes;

    uint256 public newVariable;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}


contract ERC20QuestRewards_ is Initializable, OwnableUpgradeable, PausableUpgradeable, EIP712Upgradeable, ReentrancyGuardUpgradeable, ERC2771ContextUpgradeable, ERC20QuestRewardsStorage {
    using Address for address;
    
    /* ============ Initial setup ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {}
    
    function initialize(address _intractSigner) external initializer {
        require(_intractSigner != address(0), "ERC20QuestRewards: Intract signer address must not be null address");
        __Ownable_init();
        __Pausable_init();
        __EIP712_init("IntractERC20QuestReward", "1.0.0");
        __ReentrancyGuard_init();
        intractSigner = _intractSigner;
        emit ERC20SignerUpdate(address(0), _intractSigner);
    }

    /* ============ External Functions ============ */

    function launchCampaign(
        uint96 _cid,
        uint256 _startTime,
        uint256 _claimTime,
        CampaignReward[] calldata _campaignRewards,
        bytes calldata _signature
    ) external virtual payable whenNotPaused nonReentrant {

        require(_cid > 0, "ERC20QuestRewards: Invalid cid");
        require(
            _startTime > 0 && 
            _startTime < _claimTime && 
            block.timestamp <  _claimTime,
            "ERC20QuestRewards: Invalid campaign time");
        require(campaignConfigs[_cid].admin == address(0), "ERC20QuestRewards: Campaign has been activated");

        uint256 nativeCoinsNeeded = 0;  
        for(uint256 i=0; i < _campaignRewards.length; i++) {
            address tokenAddress = _campaignRewards[i].tokenAddress;
            uint256 numRewards = _campaignRewards[i].numRewards;
            require(numRewards > 0, "ERC20QuestRewards: Invalid number of reward tokens");
            require(tokenAddress != address(0) && (tokenAddress.isContract() || tokenAddress == CurrencyTransferLib.NATIVE_TOKEN), "ERC20QuestRewards: Invalid token address");
            if(tokenAddress == CurrencyTransferLib.NATIVE_TOKEN){
                nativeCoinsNeeded += numRewards;
            }
        }
        require(msg.value == nativeCoinsNeeded, "ERC20QuestRewards: Launch campaign fail, not enough coins");

        require(
            _verify(
                _hashLaunchCampaign(_cid, _msgSender(), _startTime, _claimTime, _campaignRewards),
                _signature
            ),
            "ERC20QuestRewards: Invalid signature"
        );

        campaignConfigs[_cid] = CampaignConfig(
            _msgSender(),
            _startTime,
            _claimTime
        );

        uint96[] memory rewardIdArr = new uint96[](_campaignRewards.length); 

        for(uint256 i=0; i < _campaignRewards.length; i++) {
            address tokenAddress = _campaignRewards[i].tokenAddress;
            uint256 numRewards = _campaignRewards[i].numRewards;
            uint96 rewardId = _campaignRewards[i].rewardId;
    
            if(tokenAddress != CurrencyTransferLib.NATIVE_TOKEN){
                bool deposit = IERC20(tokenAddress).transferFrom(_msgSender(), address(this), numRewards);
                require(deposit, "ERC20QuestRewards: Launch campaign fail, not enough tokens");
            }

            rewardConfigs[rewardId] = RewardConfig(
                _cid,
                tokenAddress,
                numRewards,
                0,
                0
            );

            rewardIdArr[i] = _campaignRewards[i].rewardId;
        }

        campaignToRewards[_cid] = rewardIdArr;

        emit ERC20LaunchCampaign(_cid, _msgSender(), _startTime, _claimTime, _campaignRewards);
    }

    function claim(
        uint96 _rewardId,
        uint96 _userId,
        uint256 _amountToClaim,
        bytes calldata _signature
    ) external virtual whenNotPaused nonReentrant {
        require(_rewardId > 0, "ERC20QuestRewards: Invalid rewardId");
        require(_userId > 0, "ERC20QuestRewards: Invalid userId");
        require(_amountToClaim > 0, "ERC20QuestRewards: Invalid amount");
        require(!hasClaimed[_rewardId][_msgSender()], "ERC20QuestRewards: Already claimed");
        require(!hasClaimedUserId[_rewardId][_userId], "ERC20QuestRewards: Already claimed");

        require(
            _verify(
                _hashClaim(_rewardId, _userId, _msgSender(), _amountToClaim),
                _signature
            ),
            "ERC20QuestRewards: Invalid signature"
        );

        RewardConfig storage rewardConfig = rewardConfigs[_rewardId];
        CampaignConfig storage campaignConfig = campaignConfigs[rewardConfig.cid];

        require(rewardConfig.tokensClaimed + _amountToClaim <= rewardConfig.numRewards, "ERC20QuestRewards: Insufficient rewards available");
        require(campaignConfig.startTime < block.timestamp, "ERC20QuestRewards: Claim phase not started");
        require(block.timestamp < campaignConfig.claimTime, "ERC20QuestRewards: Claim phase ended");

        hasClaimed[_rewardId][_msgSender()] = true;
        hasClaimedUserId[_rewardId][_userId] = true;
        rewardConfig.tokensClaimed = rewardConfig.tokensClaimed + _amountToClaim;
        rewardConfig.usersClaimed = rewardConfig.usersClaimed + 1;

        if (rewardConfig.tokenAddress == CurrencyTransferLib.NATIVE_TOKEN) {
            (bool success, ) = payable(_msgSender()).call{value: _amountToClaim}(new bytes(0));
            require(success, "ERC20QuestRewards: Transfer failed");
        } else {
            bool success = IERC20(rewardConfig.tokenAddress).transfer(_msgSender(), _amountToClaim);
            require(success, "ERC20QuestRewards: Transfer failed");
        }

        emit ERC20Claim(_rewardId, _userId, _msgSender(), _amountToClaim);
    }

    function dummyClaim(
        uint96 _cid,
        uint96 _rewardId,
        uint96 _userId,
        bytes calldata _signature
    ) external virtual whenNotPaused nonReentrant {
        require(_userId > 0, "ERC20QuestRewards: Invalid userId");
        bytes32 hash = _hashDummyClaim(_cid, _rewardId, _userId, _msgSender());
        require(!usedDummyClaimHashes[hash], "ERC20QuestRewards: Already claimed");

        require(
            _verify(
                hash,
                _signature
            ),
            "ERC20QuestRewards: Invalid signature"
        );

        uint96 dummyRewardId = 1;
        uint256 _amountToClaim = 1;

        RewardConfig storage rewardConfig = rewardConfigs[dummyRewardId];
        require(rewardConfig.tokensClaimed + _amountToClaim <= rewardConfig.numRewards, "ERC20QuestRewards: Insufficient rewards available");

        usedDummyClaimHashes[hash] = true;
        rewardConfig.tokensClaimed = rewardConfig.tokensClaimed + _amountToClaim;

        if (rewardConfig.tokenAddress == CurrencyTransferLib.NATIVE_TOKEN) {
            (bool success, ) = payable(_msgSender()).call{value: _amountToClaim}(new bytes(0));
            require(success, "ERC20QuestRewards: Transfer failed");
        } else {
            bool success = IERC20(rewardConfig.tokenAddress).transfer(_msgSender(), _amountToClaim);
            require(success, "ERC20QuestRewards: Transfer failed");
        }

        emit ERC20DummyClaim(_cid, _rewardId, _userId, _msgSender());
    }


    function withdraw(uint96 _cid) external virtual whenNotPaused nonReentrant {

        require(_cid > 0, "ERC20QuestRewards: Invalid cid");
        CampaignConfig storage campaignConfig = campaignConfigs[_cid];
        require(campaignConfig.admin != address(0), "ERC20QuestRewards: Campaign not found");
        require(campaignConfig.startTime < block.timestamp, "ERC20QuestRewards: Withdraw phase not started");
        require(campaignConfig.claimTime < block.timestamp, "ERC20QuestRewards: Claim phase still active");

        uint96[] memory rewardIds = campaignToRewards[_cid];

        uint256 nativeCoinsNeeded = 0;
        for(uint256  i = 0; i < rewardIds.length; i++) {
            RewardConfig storage rewardConfig = rewardConfigs[rewardIds[i]];
            if(rewardConfig.tokensClaimed >= rewardConfig.numRewards) {
                continue;
            }

            uint256 tokensLeft = rewardConfig.numRewards - rewardConfig.tokensClaimed;
            if (rewardConfig.tokenAddress == CurrencyTransferLib.NATIVE_TOKEN) {
                nativeCoinsNeeded = nativeCoinsNeeded + tokensLeft;
            } else {
                bool success = IERC20(rewardConfig.tokenAddress).transfer(campaignConfig.admin, tokensLeft);
                require(success, "ERC20QuestRewards: Transfer failed");
            }

            rewardConfig.tokensClaimed = rewardConfig.numRewards;
            emit ERC20Withdraw(_cid, rewardIds[i], rewardConfig.tokenAddress, campaignConfig.admin, tokensLeft);

        }

        if(nativeCoinsNeeded > 0) {
            (bool success, ) = campaignConfig.admin.call{value: nativeCoinsNeeded}(new bytes(0));
            require(success, "ERC20QuestRewards: Transfer failed");
        }
    }

    /* ============ Owner Functions ============ */

    function updateSigner(address _intractSigner) external onlyOwner {
        require(_intractSigner != address(0), "ERC20QuestRewards: Invalid address");
        intractSigner = _intractSigner;
        emit ERC20SignerUpdate(intractSigner, _intractSigner);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function updateClaimTime(uint96 _cid, uint256 _newClaimTime) external onlyOwner {
        require(_cid > 0, "ERC20QuestRewards: Invalid cid");
        CampaignConfig storage campaignConfig = campaignConfigs[_cid];
        require(campaignConfig.admin != address(0), "ERC20QuestRewards: Campaign not found");
        uint256 oldClaimTime = campaignConfig.claimTime;
        campaignConfig.claimTime = _newClaimTime;
        emit ERC20ClaimTimeUpdate(_cid, oldClaimTime, _newClaimTime);
    }

    /* ============ Fallback Functions ============ */

    receive() external payable {
        // anonymous transfer: to admin
        (bool success, ) = payable(owner()).call{value: msg.value}(
            new bytes(0)
        );
        require(success, "ERC20QuestRewards: Transfer failed");
    }

    fallback() external payable {
        if (msg.value > 0) {
            // call non exist function: send to admin
            (bool success, ) = payable(owner()).call{value: msg.value}(new bytes(0));
            require(success, "ERC20QuestRewards: Transfer failed");
        }
    }

    /* ============ Internal Functions ============ */

    function _hashLaunchCampaign(
        uint96 _cid,
        address _admin,
        uint256 _startTime,
        uint256 _claimTime,
        CampaignReward[] calldata _campaignRewards
    ) internal view returns (bytes32) {

        bytes32[] memory encodedCamapignRewards = new bytes32[](_campaignRewards.length);
        for(uint256 i = 0; i < _campaignRewards.length; i++) {
            encodedCamapignRewards[i] = keccak256(
                    abi.encode(
                        ERC20_REWARD_CONFIG_TYPEHASH,
                        _campaignRewards[i].rewardId,
                        _campaignRewards[i].tokenAddress,
                        _campaignRewards[i].numRewards
                    )
                );
        }

        return
        _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ERC20_ACTIVATE_CAMPAIGN_TYPEHASH,
                    _cid,
                    _admin,
                    _startTime,
                    _claimTime,
                    keccak256(abi.encodePacked(encodedCamapignRewards))
                )
            )
        );
    }

    function _hashClaim(
        uint96 _rewardId,
        uint96 _userId,
        address _userAddress,
        uint256 _amountToClaim
    ) internal view returns (bytes32) {
        return
        _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ERC20_CLAIM_TYPEHASH,
                    _rewardId,
                    _userId,
                    _userAddress,
                    _amountToClaim
                )
            )
        );
    }

    function _hashDummyClaim(
        uint96 _cid,
        uint96 _rewardId,
        uint96 _userId,
        address _userAddress
    ) internal view returns (bytes32) {
        return
        _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ERC20_DUMMY_CLAIM_TYPEHASH,
                    _cid,
                    _rewardId,
                    _userId,
                    _userAddress
                )
            )
        );
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _verify(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == intractSigner;
    }
}

contract ERC20QuestRewardsV2 is ERC20QuestRewards_ {

    using Address for address;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _trustedForwarder) ERC20QuestRewards_(_trustedForwarder) {}

    /* ============ External Functions ============ */

    function launchCampaign(
        uint96 _cid,
        uint256 _startTime,
        uint256 _claimTime,
        CampaignReward[] calldata _campaignRewards,
        bytes calldata _signature
    ) external virtual override payable whenNotPaused nonReentrant {

        require(_cid > 0, "ERC20QuestRewards: Invalid cid");
        require(
            _startTime > 0 && 
            _startTime < _claimTime && 
            block.timestamp <  _claimTime,
            "ERC20QuestRewards: Invalid campaign time");
        require(campaignConfigs[_cid].admin == address(0), "ERC20QuestRewards: Campaign has been activated");

        uint256 nativeCoinsNeeded = 0;  
        for(uint256 i=0; i < _campaignRewards.length; i++) {
            address tokenAddress = _campaignRewards[i].tokenAddress;
            uint256 numRewards = _campaignRewards[i].numRewards;
            require(numRewards > 0, "ERC20QuestRewards: Invalid number of reward tokens");
            require(tokenAddress != address(0) && (tokenAddress.isContract() || tokenAddress == CurrencyTransferLib.NATIVE_TOKEN), "ERC20QuestRewards: Invalid token address");
            if(tokenAddress == CurrencyTransferLib.NATIVE_TOKEN){
                nativeCoinsNeeded += numRewards;
            }
        }
        require(msg.value == nativeCoinsNeeded, "ERC20QuestRewards: Launch campaign fail, not enough coins");

        require(
            _verify(
                _hashLaunchCampaign(_cid, msg.sender, _startTime, _claimTime, _campaignRewards),
                _signature
            ),
            "ERC20QuestRewards: Invalid signature"
        );

        campaignConfigs[_cid] = CampaignConfig(
            msg.sender,
            _startTime,
            _claimTime
        );

        uint96[] memory rewardIdArr = new uint96[](_campaignRewards.length); 

        for(uint256 i=0; i < _campaignRewards.length; i++) {
            address tokenAddress = _campaignRewards[i].tokenAddress;
            uint256 numRewards = _campaignRewards[i].numRewards;
            uint96 rewardId = _campaignRewards[i].rewardId;
    
            if(tokenAddress != CurrencyTransferLib.NATIVE_TOKEN){
                bool deposit = IERC20(tokenAddress).transferFrom(msg.sender, address(this), numRewards);
                require(deposit, "ERC20QuestRewards: Launch campaign fail, not enough tokens");
            }

            rewardConfigs[rewardId] = RewardConfig(
                _cid,
                tokenAddress,
                numRewards,
                0,
                0
            );

            rewardIdArr[i] = _campaignRewards[i].rewardId;
        }

        campaignToRewards[_cid] = rewardIdArr;

        emit ERC20LaunchCampaign(_cid, msg.sender, _startTime, _claimTime, _campaignRewards);
    }

    function version2() external pure returns (bool success) {
        return true;
    }
}

