//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IERC20Metadata.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20.sol";

import "./SpecialConfigurePoolLibrary.sol";
import "./SpecialEndPoolLibrary.sol";
import "./SpecialDeployPoolLibrary.sol";
import "./SpecialDepositPoolLibrary.sol";
import "./ISpecialPool.sol";
import "./SpecialValidatePoolLibrary.sol";
import "./SpecialSaleExtra.sol";

contract SpecialSale is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    SpecialSaleExtra private constant specialSaleExtra =
        SpecialSaleExtra(0x5FaeD0dB185AD9235E2dEA35d98C07eF3B521b72);
    address public constant treasury =
        address(0xDf47F618a94eEC71c2eD8cFad256942787E0d951);
    IIDO public constant ido=IIDO(0x6126E7Af6989cfabD2be277C46fB507aa5836CFd);
    address[] public poolAddresses;
    uint256[] public poolFixedFee;
    uint256 public poolPercentFee;
    uint256 public poolTokenPercentFee;
    mapping(address => address) public poolOwners;
    mapping(address => ISpecialPool.PoolModel) public poolInformation;
    mapping(address => ISpecialPool.PoolDetails) public poolDetails;
    mapping(address => address[]) public participantsAddress;
    mapping(address => mapping(address => uint256)) public collaborations;
    mapping(address => uint256) public _weiRaised;
    mapping(address => mapping(address => bool)) public _didRefund;
    mapping(address => mapping(address => bool))
        private whitelistedAddressesMap;
    mapping(address => address[]) public whitelistedAddressesArray;
    mapping(address => bool) public isHiddenPool;
    address public holdingToken;
    uint256[] public holdingTokenAmount;
    mapping(address => ISpecialPool.UserVesting) public userVesting;
    mapping(address => mapping(address => uint256))
        public unlockedVestingAmount;
    mapping(address => uint256) public cliff;
    mapping(address => bool) public isAdminSale;
    mapping(address => address) public fundRaiseToken;
    mapping(address => uint256) public fundRaiseTokenDecimals;
    mapping(address => uint256) public allowDateTime;
    uint256 gweiLimit;
    address public holdingStakedToken;
    uint256[] public holdingStakedTokenAmount;
    mapping(address => bool) public isTieredWhitelist;
    mapping(address => mapping(address => bool))
        private whitelistedAddressesMapForTiered;
    mapping(address => address[]) public whitelistedAddressesArrayForTiered;
    uint256 private amountInit;
    uint256 private amountAddedPerSec;
    uint256 private limitPeriod;
    mapping(address=>mapping(uint256=>uint256)) depositAmount;
    address public holdingNFT;
    mapping(address => bool) public noTier; 
    event LogPoolCreated(
        address poolOwner,
        address pool,
        ISpecialPool.PoolModel model,
        ISpecialPool.PoolDetails details,
        ISpecialPool.UserVesting userVesting,
        uint256 cliff,
        bool isAdminSale,
        bool isTieredWhitelist,
        address fundRaiseToken,
        uint256 fundRaiseTokenDecimals,
        uint256 allowDateTime
    );
    event LogPoolKYCUpdate(address pool, bool kyc);
    event LogPoolAuditUpdate(address pool, bool audit, string auditLink);
    event LogPoolTierUpdate(address pool, uint256 tier);
    event LogPoolExtraData(address pool, string extraData);
    event LogDeposit(address pool, address participant, uint256 weiRaised, uint256 decimals);
    event LogPoolStatusChanged(address pool, uint256 status);
    event LogConfigChanged(
        uint256[] poolFixedFee,
        uint256 poolPercentFee,
        uint256 poolTokenPercentFee
    );
    event LogAddressWhitelisted(
        address pool,
        address[] whitelistedAddresses,
        address[] whitelistedAddressesForTiered
    );
    event TierAllowed(address pool, bool isAllowed);
    event LogUpdateWhitelistable(address pool, bool[2] whitelistable);
    event LogPoolHide(address pool, bool isHide);
    event LogAdminPoolFilled(
        address sender,
        address pool,
        address projectTokenAddress,
        uint256 decimals,
        uint256 totalSupply,
        string symbol,
        string name
    );
    event LogUpdateAllowDateTime(address pool, uint256 allowDateTime);
    event LogEmergencyWithdraw(
        address _pool,
        address participant,
        uint256 weiRaised, 
        uint256 decimals
    );
    modifier _onlyPoolOwner(address _pool, address _owner) {
        require(poolOwners[_pool] == _owner, "Not Owner!");
        _;
    }
    modifier _onlyPoolOwnerAndOwner(address _pool, address _owner) {
        require(poolOwners[_pool] == _owner || _owner == owner(), "Not Owner!");
        _;
    }

    function initialize(
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();        
    }

    function createPool(
        ISpecialPool.PoolModel calldata model,
        ISpecialPool.PoolDetails calldata details,
        ISpecialPool.UserVesting calldata _userVesting,
        uint256 _cliff,
        bool _isAdminSale,
        bool _isTieredWhitelist,
        address _fundRaiseToken,
        uint256 _allowDateTime
    ) external payable nonReentrant returns (address poolAddress) {
        require(!_isAdminSale || msg.sender == owner(), "not Admin!");
        require(
            (_isAdminSale || msg.value >= poolFixedFee[uint256(details.tier)]),
            "Not enough fee!"
        );
        poolAddress = SpecialDeployPoolLibrary.deployPool();
        if (_fundRaiseToken == address(0))
            fundRaiseTokenDecimals[poolAddress] = 18;
        else {
            IERC20Metadata _token = IERC20Metadata(_fundRaiseToken);
            uint256 _decimals = _token.decimals();
            if (_decimals > 0) {
                fundRaiseToken[poolAddress] = _fundRaiseToken;
                fundRaiseTokenDecimals[poolAddress] = _decimals;
            } else fundRaiseTokenDecimals[poolAddress] = 18;
        }

        poolInformation[poolAddress] = ISpecialPool.PoolModel({
            hardCap: model.hardCap,
            softCap: model.softCap,
            specialSaleRate: model.specialSaleRate,
            projectTokenAddress: model.projectTokenAddress,
            status: ISpecialPool.PoolStatus.Inprogress,
            startDateTime: model.startDateTime,
            endDateTime: model.endDateTime,
            minAllocationPerUser: model.minAllocationPerUser,
            maxAllocationPerUser: model.maxAllocationPerUser
        });
        allowDateTime[poolAddress] = _allowDateTime;
        isAdminSale[poolAddress] = _isAdminSale;
        SpecialValidatePoolLibrary._preValidatePoolCreation(poolInformation[poolAddress], _isAdminSale, _allowDateTime);

        poolDetails[poolAddress] = ISpecialPool.PoolDetails({
            extraData: details.extraData,
            whitelistable: details.whitelistable,
            audit: false,
            auditLink: "",
            tier: details.tier,
            kyc: false
        });
        if (!poolDetails[poolAddress].whitelistable) {
            require(!_isTieredWhitelist, "not whitelist");
        }
        isTieredWhitelist[poolAddress] = _isTieredWhitelist;
        userVesting[poolAddress] = _userVesting;
        cliff[poolAddress] = _cliff;
        SpecialValidatePoolLibrary._preValidateUserVesting(userVesting[poolAddress], _cliff);

        if (!_isAdminSale)
            SpecialDeployPoolLibrary.initPool(
                poolAddress,
                owner(),
                poolInformation[poolAddress],
                poolTokenPercentFee,
                fundRaiseTokenDecimals[poolAddress]
            );

        poolAddresses.push(poolAddress);
        poolOwners[poolAddress] = msg.sender;
        emit LogPoolCreated(
            msg.sender,
            poolAddress,
            poolInformation[poolAddress],
            poolDetails[poolAddress],
            userVesting[poolAddress],
            _cliff,
            _isAdminSale,
            _isTieredWhitelist,
            fundRaiseToken[poolAddress],
            fundRaiseTokenDecimals[poolAddress],
            _allowDateTime
        );
    }

    function updateAllowDateTime(address _pool, uint256 _allowDateTime)
        external
        nonReentrant
        onlyOwner
    {
        require(
            (poolInformation[_pool].hardCap == _weiRaised[_pool] &&
                _allowDateTime >=
                poolInformation[_pool].startDateTime) ||
                (_allowDateTime >= poolInformation[_pool].endDateTime),
            "allow>=end!"
        );
        allowDateTime[_pool] = _allowDateTime;
        poolInformation[_pool].endDateTime=_allowDateTime;
        emit LogUpdateAllowDateTime(_pool, _allowDateTime);
    }

    function fillAdminPool(address poolAddress, address _projectTokenAddress)
        external
        nonReentrant
        onlyOwner
    {
        require(isAdminSale[poolAddress], "not Admin!");
        uint256 decimals;
        uint256 totalSupply;
        string memory symbol;
        string memory name;
        if (poolInformation[poolAddress].projectTokenAddress == address(0)) {
            poolInformation[poolAddress]
                .projectTokenAddress = _projectTokenAddress;
        }
        IERC20Metadata token = IERC20Metadata(
            poolInformation[poolAddress].projectTokenAddress
        );
        decimals = token.decimals();
        totalSupply = token.totalSupply();
        symbol = token.symbol();
        name = token.name();
        SpecialDeployPoolLibrary.fillAdminPool(
            poolAddress,
            poolInformation[poolAddress],
            decimals,
            _weiRaised[poolAddress],
            fundRaiseTokenDecimals[poolAddress]>0 ? fundRaiseTokenDecimals[poolAddress] : 18
        );
        emit LogAdminPoolFilled(
            msg.sender,
            poolAddress,
            poolInformation[poolAddress].projectTokenAddress,
            decimals,
            totalSupply,
            symbol,
            name
        );
    }

    function updateTierAllowed(
        address _pool,
        bool isAllowed
    ) external onlyOwner{
        noTier[_pool]=isAllowed;
        emit TierAllowed(_pool, isAllowed);       
    }

    function setAdminConfig(
        uint256[] memory _poolFixedFee,
        uint256 _poolPercentFee,
        uint256 _poolTokenPercentFee,
        uint256 _gweiLimit
    ) public onlyOwner {
        poolFixedFee = _poolFixedFee;
        poolPercentFee = _poolPercentFee;
        poolTokenPercentFee = _poolTokenPercentFee;        
        gweiLimit = _gweiLimit;
    }

    // function setAdminLimit(
    //     uint256 _amountInit,
    //     uint256 _amountAddedPerSec,
    //     uint256 _limitPeriod
    // ) public onlyOwner {
    //     amountInit=_amountInit;
    //     amountAddedPerSec=_amountAddedPerSec;
    //     limitPeriod=_limitPeriod;
    // }
    function updateExtraData(address _pool, string memory _extraData)
        external
        _onlyPoolOwner(_pool, msg.sender)
    {
        SpecialConfigurePoolLibrary.updateExtraData(
            _extraData,
            poolInformation[_pool],
            poolDetails[_pool]
        );
        emit LogPoolExtraData(_pool, _extraData);
    }

    function updateKYCStatus(address _pool, bool _kyc) external onlyOwner {
        SpecialConfigurePoolLibrary.updateKYCStatus(_kyc, poolDetails[_pool]);
        emit LogPoolKYCUpdate(_pool, _kyc);
    }

    function updateAuditStatus(
        address _pool,
        bool _audit,
        string memory _auditLink
    ) external {
        require((poolOwners[_pool] == msg.sender && uint256(poolDetails[_pool].tier)>0) || msg.sender == owner(), "Not Special sale Owner or less than gold tier!");
        SpecialConfigurePoolLibrary.updateAuditStatus(
            _audit,
            _auditLink,
            poolDetails[_pool]
        );
        emit LogPoolAuditUpdate(_pool, _audit, _auditLink);
    }

    function updateTierStatus(address _pool, uint256 _tier) external onlyOwner {
        poolDetails[_pool].tier = ISpecialPool.PoolTier(_tier);
        emit LogPoolTierUpdate(_pool, _tier);
    }

    function addAddressesToWhitelist(
        address _pool,
        address[] memory whitelistedAddresses,
        address[] memory whitelistedAddressesForTiered
    ) external _onlyPoolOwner(_pool, msg.sender) {
        if (poolDetails[_pool].whitelistable) {
            SpecialConfigurePoolLibrary.addAddressesToWhitelist(
                whitelistedAddresses,
                poolInformation[_pool],
                whitelistedAddressesMap[_pool],
                whitelistedAddressesArray[_pool]
            );
            if (isTieredWhitelist[_pool]) {
                SpecialConfigurePoolLibrary.addAddressesToWhitelistForTiered(
                    whitelistedAddressesForTiered,
                    poolInformation[_pool],
                    whitelistedAddressesMapForTiered[_pool],
                    whitelistedAddressesArrayForTiered[_pool]
                );
                emit LogAddressWhitelisted(
                    _pool,
                    whitelistedAddresses,
                    whitelistedAddressesForTiered
                );
            }else{
                emit LogAddressWhitelisted(
                    _pool,
                    whitelistedAddresses,
                    new address[](0)
                );
            }                
        }
    }

    function updateWhitelistable(address _pool, bool[2] memory whitelistable)
        external
        _onlyPoolOwner(_pool, msg.sender)
    {
        SpecialConfigurePoolLibrary.updateWhitelistable(
            _pool,
            whitelistable,
            isTieredWhitelist,
            poolInformation[_pool],
            poolDetails[_pool],
            whitelistedAddressesMap[_pool],
            whitelistedAddressesArray,
            whitelistedAddressesMapForTiered[_pool],
            whitelistedAddressesArrayForTiered
        );
        emit LogUpdateWhitelistable(_pool, whitelistable);
    }

    function deposit(address _pool, uint256 _amount) external payable {
        require(tx.gasprice <= gweiLimit, "No sniping!");
        require(poolOwners[_pool] != address(0x0), "Not Existed!");        
        bool isPassed=!poolDetails[_pool].whitelistable ? true : SpecialDepositPoolLibrary.whitelistCheckForNFTAndAccount(
                uint256(poolDetails[_pool].tier),
                isTieredWhitelist[_pool],
                poolInformation[_pool].startDateTime,    
                ido                
            );
        if(!isPassed)   
        {
            isPassed=SpecialDepositPoolLibrary.whitelistCheckForTokenHolders(
                ido.holdingToken(), 
                ido.holdingStakedToken(),
                [
                    ido.holdingTokenAmount(uint256(poolDetails[_pool].tier)),
                    ido.holdingStakedTokenAmount(uint256(poolDetails[_pool].tier)),
                    ido.holdingTokenAmount(3),
                    ido.holdingStakedTokenAmount(3),
                    uint256(poolDetails[_pool].tier),
                    poolInformation[_pool].startDateTime
                ],
                isTieredWhitelist[_pool]
            );
            if(!isPassed)
                SpecialDepositPoolLibrary.whitelistCheck(
                    isTieredWhitelist[_pool],
                    poolInformation[_pool].startDateTime,
                    whitelistedAddressesMap[_pool],
                    whitelistedAddressesMapForTiered[_pool]
                );
        }
        {
            SpecialDepositPoolLibrary.depositPool(
                [_pool, fundRaiseToken[_pool]],
                _weiRaised,
                poolInformation[_pool],
                collaborations[_pool],
                participantsAddress,
                _amount
            );
        }

        if (fundRaiseToken[_pool] == address(0)) {
            emit LogDeposit(_pool, msg.sender, _weiRaised[_pool], fundRaiseTokenDecimals[_pool]>0 ? fundRaiseTokenDecimals[_pool] : 18);
        } else emit LogDeposit(_pool, msg.sender, _weiRaised[_pool], fundRaiseTokenDecimals[_pool]>0 ? fundRaiseTokenDecimals[_pool] : 18);
    }

    // old contract usable from here
    function cancelPool(address _pool)
        external
        _onlyPoolOwnerAndOwner(_pool, msg.sender)
        nonReentrant
    {
        SpecialEndPoolLibrary.cancelPool(
            poolInformation[_pool],
            poolOwners[_pool],
            _pool
        );

        emit LogPoolStatusChanged(
            _pool,
            uint256(ISpecialPool.PoolStatus.Cancelled)
        );
    }

    function forceCancelPool(address _pool) external onlyOwner nonReentrant {
        SpecialEndPoolLibrary.forceCancelPool(poolInformation[_pool]);
        emit LogPoolStatusChanged(
            _pool,
            uint256(ISpecialPool.PoolStatus.Cancelled)
        );
    }

    function claimToken(address _pool) external nonReentrant {
        SpecialEndPoolLibrary.claimToken(
            poolInformation[_pool],
            collaborations[_pool],
            unlockedVestingAmount[_pool],
            userVesting[_pool],
            _didRefund[_pool],
            _pool,
            cliff[_pool],
            fundRaiseTokenDecimals[_pool]>0 ? fundRaiseTokenDecimals[_pool] : 18
        );
    }

    function refund(address _pool) external nonReentrant {
        SpecialEndPoolLibrary.refund(
            _pool,
            _weiRaised[_pool],
            _didRefund[_pool],
            collaborations[_pool],
            poolInformation[_pool],
            fundRaiseToken[_pool]
        );
    }

    function collectFunds(address _pool)
        external
        _onlyPoolOwner(_pool, msg.sender)
    {
        SpecialEndPoolLibrary.collectFunds(
            [_pool, owner(), poolOwners[_pool], fundRaiseToken[_pool]],
            [
                _weiRaised[_pool],
                poolPercentFee,
                poolTokenPercentFee,
                fundRaiseTokenDecimals[_pool]>0 ? fundRaiseTokenDecimals[_pool] : 18
            ],
            poolInformation[_pool],
            isAdminSale[_pool]
        );
        emit LogPoolStatusChanged(
            _pool,
            uint256(ISpecialPool.PoolStatus.Collected)
        );
    }

    function allowClaim(address _pool)
        external
        _onlyPoolOwnerAndOwner(_pool, msg.sender)
    {
        SpecialEndPoolLibrary.allowClaim(
            [_pool, owner(), fundRaiseToken[_pool]],
            [_weiRaised[_pool], fundRaiseTokenDecimals[_pool]>0 ? fundRaiseTokenDecimals[_pool] : 18],
            poolInformation[_pool],
            isAdminSale[_pool],
            allowDateTime[_pool]
        );
        emit LogPoolStatusChanged(
            _pool,
            uint256(ISpecialPool.PoolStatus.Allowed)
        );
    }

    function updateHidePool(address pool, bool isHide) external onlyOwner {
        SpecialConfigurePoolLibrary.updateHidePool(pool, isHide, isHiddenPool);
        emit LogPoolHide(pool, isHide);
    }

    function emergencyWithdraw(address _pool) external nonReentrant {
        bool isWithdrawn = SpecialEndPoolLibrary.emergencyWithdraw(
            _pool,
            treasury,
            _weiRaised,
            collaborations[_pool],
            participantsAddress[_pool],
            poolInformation[_pool],
            fundRaiseToken[_pool]
        );
        if (isWithdrawn) emit LogEmergencyWithdraw(_pool, msg.sender, _weiRaised[_pool], fundRaiseTokenDecimals[_pool]>0 ? fundRaiseTokenDecimals[_pool] : 18);
    }
    receive() external payable {}

    function getPoolAddresses() external view returns (address[] memory) {
        return poolAddresses;
    }
    function getParticipantsAddresses(address _pool) external view returns (address[] memory) {
        return participantsAddress[_pool];
    }

    function getWhitelistAddresses(address _pool) external view returns (address[] memory t1, address[] memory t2) {
        t1= whitelistedAddressesArray[_pool];
        t2= whitelistedAddressesArrayForTiered[_pool];
    }
}

