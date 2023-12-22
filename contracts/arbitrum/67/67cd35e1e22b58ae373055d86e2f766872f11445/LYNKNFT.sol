// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./baseContract.sol";
import "./IUser.sol";
import "./ILYNKNFT.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./draft-IERC20PermitUpgradeable.sol";
import "./INode.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract LYNKNFT is ILYNKNFT, ERC721EnumerableUpgradeable, baseContract {
    uint256 private randomSeed;
    mapping(uint256 => uint256[]) public nftInfo;
    mapping(address => MintInfo) public mintInfoOf;
    mapping(string => bool) public nameUsed;
    mapping(uint256 => AttributeAddedInfo) public addedVAInfoOf;

    uint256 public earlyBirdCounter;
    // @Deprecated
    uint256 public earlyBirdWlCounter;
    mapping(address => bool) public earlyBirdMintedOf;

    event Mint(uint256 indexed tokenId, uint256[] nftInfo, string name, address payment, uint256 amount);
    event Upgrade(uint256 indexed tokenId, Attribute attr, uint256 point);

    uint256 public version = 1;

    struct MintInfo {
        uint128 lastMintTime;
        uint128 mintNumInDuration;
    }

    struct AttributeAddedInfo {
        uint128 lastAddedTime;
        uint128 addedInDuration;
    }

    //V2 add activity mint
    ActivityMintInfo public _activityMintInfo;
    struct ActivityMintInfo {
        uint128 startTime;
        uint128 endTime;
        uint256 startId;
        uint256 endId;
        uint256 mintPrice;
        uint256 mintCount;
        uint256 maxCount;
    }
    event ActivityMint(address indexed user,uint256 indexed tokenId,uint256 price);

    //V3 add activity mint limit
    mapping(uint128 => mapping(address => bool)) public _activityMinted;

    //v4 add node mint
    mapping(address => bool) public _nodeMinted;
    mapping(uint256 => uint256) public _isNodeNft;
    mapping(address => uint256) public _userNodeNft;

    event NodeMint(address indexed user,uint256 indexed tokenId,uint256 price,uint256 nodetype);

    constructor(address dbAddress) baseContract(dbAddress){

    }

    function __LYNKNFT_init() public initializer {
        __LYNKNFT_init_unchained();
        __ERC721Enumerable_init();
        __ERC721_init("LYNKNFT","LYNKNFT");
        __baseContract_init();
    }

    function __LYNKNFT_init_unchained() private {
        _randomSeedGen();
    }

    // function earlyBirdMintWIthPermit(uint256 _amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
    //     require(DBContract(DB_CONTRACT).earlyBirdMintWlOf(_msgSender()), 'LYNKNFT: not in the wl.');
    //     // require(earlyBirdWlCounter < DBContract(DB_CONTRACT).wlNum(), 'LYNKNFT: wl num limit.');

    //     IERC20PermitUpgradeable(
    //         DBContract(DB_CONTRACT).earlyBirdMintPayment()
    //     ).permit(_msgSender(), address(this), _amount, deadline, v, r, s);
    //     // earlyBirdWlCounter++;

    //     _earlyBirdMint(DBContract(DB_CONTRACT).rootAddress());
    // }

    function earlyBirdMint() external {
        require(
            DBContract(DB_CONTRACT).earlyBirdMintWlOf(_msgSender()) ||
            IUser(DBContract(DB_CONTRACT).USER_INFO()).isValidUser(_msgSender()),
                'invalid address.'
        );
        // require(earlyBirdWlCounter < DBContract(DB_CONTRACT).wlNum(), 'LYNKNFT: wl num limit.');
        // earlyBirdWlCounter++;

        _earlyBirdMint(DBContract(DB_CONTRACT).rootAddress());
    }

    // function refEarlyBirdMintWIthPermit(address _refAddress, uint256 _amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
    //     // require(DBContract(DB_CONTRACT).earlyBirdMintWlOf(_refAddress), 'LYNKNFT: not in the wl.');
    //     require(_refAddress != DBContract(DB_CONTRACT).rootAddress(), 'LYNKNFT: not in the wl.');

    //     IERC20PermitUpgradeable(
    //         DBContract(DB_CONTRACT).earlyBirdMintPayment()
    //     ).permit(_msgSender(), address(this), _amount, deadline, v, r, s);

    //     _earlyBirdMint(_refAddress);
    // }

    function refEarlyBirdMint(address _refAddress) external {
        // require(DBContract(DB_CONTRACT).earlyBirdMintWlOf(_refAddress), 'LYNKNFT: not in the wl.');
        require(
            !IUser(DBContract(DB_CONTRACT).USER_INFO()).isValidUser(_msgSender()) ||
            earlyBirdMintedOf[_msgSender()],
                'call with earlyBirdMint.'
        );
        require(DBContract(DB_CONTRACT).earlyBirdMintWlOf(_refAddress), 'not in the wl.');

        _earlyBirdMint(_refAddress);
    }

    function earlyMintInfo() external view returns (uint256 _totalNum, uint256 _remainNum, uint256 _nextId) {
        (uint256 _startId, uint256 _endId) = DBContract(DB_CONTRACT).earlyBirdMintIdRange();
        _totalNum = _endId - _startId;
        _remainNum = _totalNum - earlyBirdCounter;
        _nextId = _startId + earlyBirdCounter;
    }

    function mintWithPermit(uint256 _tokenId, address _payment, string calldata _name, uint256 _amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        IERC20PermitUpgradeable(_payment).permit(_msgSender(), address(this), _amount, deadline, v, r, s);
        _mint(_tokenId, _payment, _name);
    }

    function mint(uint256 _tokenId, address _payment, string calldata _name) external {
        _mint(_tokenId, _payment, _name);
    }

    function upgradeWithPermit(Attribute _attr, uint256 _tokenId, uint256 _point, address _payment, uint256 _amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        IERC20PermitUpgradeable(_payment).permit(_msgSender(), address(this), _amount, deadline, v, r, s);
        _upgrade(_attr, _tokenId, _point, _payment);
    }

    function upgrade(Attribute _attr, uint256 _tokenId, uint256 _point, address _payment) external {
        _upgrade(_attr, _tokenId, _point, _payment);
    }

    function nftInfoOf(uint256 _tokenId) external view override returns (uint256[] memory _nftInfo) {
        return nftInfo[_tokenId];
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    function _attributesGen(address _minter) private returns (uint256 _vitality, uint256 _intellect) {
        uint256 _randomSeed = _randomSeedGen();
        _randomSeed = uint256(keccak256(abi.encodePacked(_randomSeed, _minter)));
        _vitality = ((_randomSeed & 0xff) % 5) + 1;
        _intellect = (((_randomSeed >> 128) & 0xff) % 3) + 1;
    }

    function _randomSeedGen() private returns (uint256 _randomSeed) {
        _randomSeed = uint256(keccak256(abi.encodePacked(randomSeed, block.timestamp, block.difficulty)));
        randomSeed = _randomSeed;
    }

    /// @dev Returns an URI for a given token ID
    function _baseURI() internal view virtual override returns (string memory) {
        return DBContract(DB_CONTRACT).baseTokenURI();
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        string memory url = super.tokenURI(tokenId); 
        return bytes(url).length > 0 ? string(abi.encodePacked(url,".json")) : "";
    }

    function _mintPrice(uint256 _tokenId, address _payment, address _user) private view returns (uint256) {
        require(
            DBContract(DB_CONTRACT).LRT_TOKEN() == _payment ||
            DBContract(DB_CONTRACT).USDT_TOKEN() == _payment,
            'unsupported payment.'
        );
        uint256 decimal = IERC20MetadataUpgradeable(_payment).decimals();
        uint256 mintPrice;
        if (_tokenId >= 300_000) {
            mintPrice = DBContract(DB_CONTRACT).mintPrices(2) * (10 ** decimal);
        } else if (_tokenId >= 200_000) {
            mintPrice = DBContract(DB_CONTRACT).mintPrices(1) * (10 ** decimal);
        } else {
            mintPrice = DBContract(DB_CONTRACT).mintPrices(0) * (10 ** decimal);
        }
        require(_tokenId >= 100_000, 'reverse token id.');
        require(_tokenId < 400_000, 'token id too large.');

        //V2 add activity mint
        if(isActivityMint(_tokenId,_user)){
            mintPrice = _activityMintInfo.mintPrice * (10 ** decimal);
        }

        return mintPrice;
    }

    function _earlyBirdMint(address _refAddress) private {
        require(DBContract(DB_CONTRACT).earlyBirdMintEnable(), 'mint yet.');

        require(!earlyBirdMintedOf[_msgSender()], 'minted.');
        earlyBirdMintedOf[_msgSender()] = true;

        address userContractAddress = DBContract(DB_CONTRACT).USER_INFO();

        // require(!IUser(userContractAddress).isValidUser(_msgSender()), 'LYNKNFT: already minted.');
        if (!IUser(userContractAddress).isValidUser(_msgSender())) {
            IUser(userContractAddress).registerByEarlyPlan(_msgSender(), _refAddress);
        }

        (uint256 _startId, uint256 _endId) = DBContract(DB_CONTRACT).earlyBirdMintIdRange();
        uint256 _earlyBirdCurrentId = _startId + earlyBirdCounter;
        require(_earlyBirdCurrentId < _endId, 'sold out.');
        // require(_earlyBirdCurrentId + (DBContract(DB_CONTRACT).wlNum() - earlyBirdWlCounter) < _endId, 'LYNKNFT: sold out.');
        earlyBirdCounter++;
        string memory _name = string(abi.encodePacked(StringsUpgradeable.toString(_earlyBirdCurrentId), ".lynk"));

        (address payment, uint256 price) = DBContract(DB_CONTRACT).earlyBirdMintPrice();
        _pay(payment, _msgSender(), price,IUser.REV_TYPE.USDT_ADDR);
        nftInfo[_earlyBirdCurrentId] = [ DBContract(DB_CONTRACT).earlyBirdInitCA(), 0, 0, 0];
        ERC721Upgradeable._safeMint(_msgSender(), _earlyBirdCurrentId);
        emit Mint(_earlyBirdCurrentId, nftInfo[_earlyBirdCurrentId], _name, payment, price);
    }

    function _mint(uint256 _tokenId, address _payment, string calldata _name) private {
        require(DBContract(DB_CONTRACT).commonMintEnable(), 'mint yet.');

        require(
            IUser(DBContract(DB_CONTRACT).USER_INFO()).isValidUser(_msgSender()),
            'invalid user.'
        );
        require(!nameUsed[_name], 'in used.');
        require(!_isReverseName(_name), 'reversed name.');
        nameUsed[_name] = true;

        MintInfo memory mintInfo = mintInfoOf[_msgSender()];
        if (block.timestamp - mintInfo.lastMintTime >= DBContract(DB_CONTRACT).duration()) {
            mintInfo.mintNumInDuration = 0;
            mintInfoOf[_msgSender()].lastMintTime = uint128(block.timestamp);
        }
        require(
            mintInfo.mintNumInDuration < DBContract(DB_CONTRACT).maxMintPerDayPerAddress(),
            'mint more'
        );
        mintInfoOf[_msgSender()].mintNumInDuration = mintInfo.mintNumInDuration + 1;

        uint256 mintPrice = _mintPrice(_tokenId, _payment,_msgSender());
        
        //V2 add activity mint
        if(mintPrice>0){
            _pay(_payment, _msgSender(), mintPrice,IUser.REV_TYPE.MINT_NFT_ADDR);
        }
        if(isActivityMint(_tokenId,_msgSender())){
            _activityMinted[_activityMintInfo.startTime][_msgSender()]=true;
            _activityMintInfo.mintCount=_activityMintInfo.mintCount+1;
            emit ActivityMint(_msgSender(),_tokenId,mintPrice);
        }

        (uint256 vitality, uint256 intellect) = _attributesGen(_msgSender());
        nftInfo[_tokenId] = [ 0, vitality, intellect, 0];
        ERC721Upgradeable._safeMint(_msgSender(), _tokenId);

        emit Mint(_tokenId, nftInfo[_tokenId], string(abi.encodePacked(_name, ".lynk")), _payment, mintPrice);
    }

    function _upgrade(Attribute _attr, uint256 _tokenId, uint256 _point, address _payment) private {
        require(
            IUser(DBContract(DB_CONTRACT).USER_INFO()).isValidUser(_msgSender()),
            'not a valid user.'
        );

        // avoid upgrade while staking
        require(
            tx.origin == _msgSender() &&
            ERC721Upgradeable.ownerOf(_tokenId) == _msgSender(),
            'not the owner'
        );

        if (Attribute.charisma == _attr) {
            require(
                _payment == DBContract(DB_CONTRACT).USDT_TOKEN() ||
                _payment == DBContract(DB_CONTRACT).LRT_TOKEN(),
                'unsupported payment'
            );
        } else {
            if (Attribute.vitality == _attr) {
                AttributeAddedInfo memory addedInfo = addedVAInfoOf[_tokenId];
                if (block.timestamp - addedInfo.lastAddedTime >= DBContract(DB_CONTRACT).duration()) {
                    addedInfo.addedInDuration = 0;
                    addedVAInfoOf[_tokenId].lastAddedTime = uint128(block.timestamp);
                }
                require(
                    addedInfo.addedInDuration + _point <= DBContract(DB_CONTRACT).maxVAAddPerDayByTokenId(_tokenId),
                        'upgrade more'
                );
                addedVAInfoOf[_tokenId].addedInDuration = addedInfo.addedInDuration + uint128(_point);
            } else {
                uint256 preAttrIndex = uint256(_attr) - 1;
                (uint256 preAttrLevel,) = DBContract(DB_CONTRACT).calcLevel(Attribute(preAttrIndex), nftInfo[_tokenId][preAttrIndex]);
                (uint256 curAttrLevelAfterUpgrade, uint256 curAttrLevelOverflowAfterUpgrade) = DBContract(DB_CONTRACT).calcLevel(_attr, _point + nftInfo[_tokenId][uint256(_attr)]);
                require(
                    preAttrLevel > curAttrLevelAfterUpgrade ||
                    (preAttrLevel == curAttrLevelAfterUpgrade && curAttrLevelOverflowAfterUpgrade == 0),
                    'level'
                );
                if (Attribute.intellect == _attr) {
                    (uint256 vaAttrLevel,) = DBContract(DB_CONTRACT).calcLevel(Attribute.charisma, nftInfo[_tokenId][uint256(Attribute.charisma)]);
                    require(
                        vaAttrLevel > curAttrLevelAfterUpgrade ||
                        (vaAttrLevel == curAttrLevelAfterUpgrade && curAttrLevelOverflowAfterUpgrade == 0),
                        'level'
                    );
                }
            }

            require(_payment == DBContract(DB_CONTRACT).AP_TOKEN(), 'unsupported payment.');
        }

        uint256 decimal = IERC20MetadataUpgradeable(_payment).decimals();
        uint256 amount = _point * (10 ** decimal);
        _pay(_payment, _msgSender(), amount,(Attribute.charisma == _attr) ? IUser.REV_TYPE.UP_CA_ADDR:IUser.REV_TYPE.AP_ADDR);

        nftInfo[_tokenId][uint256(_attr)] += _point;
        emit Upgrade(_tokenId, _attr, _point);

        // dealing with the ref things.
        IUser(DBContract(DB_CONTRACT).USER_INFO()).hookByUpgrade(_msgSender(), Attribute.charisma == _attr ? _point : 0);
    }

    function isReverseName(string memory _name) external pure returns (bool) {
        return _isReverseName(_name);
    }

    function _isReverseName(string memory _name) private pure returns (bool) {
        bytes memory b = bytes(_name);
        uint256 _nameUint = 0;
        for(uint256 i = 0; i < b.length; i++) {
            if (i == 0 && uint8(b[i]) == 48 && b.length > 0) {
                return false;
            }

            if(uint8(b[i]) < 48 || uint8(b[i]) > 57) {
                return false;
            }
            _nameUint = _nameUint * 10 + (uint8(b[i]) - 48);
        }
        return _nameUint < 100000;
    }

    //V2 add activity mint
    function isActivityMint(uint256 _tokenId,address _user) public view returns (bool) {
        if(_activityMintInfo.startTime<=0){
            return false;
        }
        return (
            _activityMinted[_activityMintInfo.startTime][_user] != true && 
            uint128(block.timestamp) >= _activityMintInfo.startTime && 
            uint128(block.timestamp) <= _activityMintInfo.endTime &&
            _activityMintInfo.mintCount < _activityMintInfo.maxCount &&
            _tokenId >= _activityMintInfo.startId && 
            _tokenId <= _activityMintInfo.endId
        );
    }

    function setActivityMint(uint128 _startTime,uint128 _endTime,uint256 _startId,uint256 _endId,uint256 _mintMax,uint256 _price) public {
       require(_msgSender() == DBContract(DB_CONTRACT).operator());
       _activityMintInfo.startTime=_startTime;
       _activityMintInfo.endTime=_endTime;
       _activityMintInfo.startId=_startId;
       _activityMintInfo.endId=_endId;
       _activityMintInfo.maxCount=_mintMax;
       _activityMintInfo.mintPrice=_price;
       _activityMintInfo.mintCount=0;
    }

    function getActivityMint() public view returns(ActivityMintInfo memory info) {
        return _activityMintInfo;
    }

    //v4 add node mint
    function mintNode(uint256 _t,uint256 _n, string calldata _name) external {
        //check
        require(DBContract(DB_CONTRACT).nftMintEnable(), 'mint yet.');
        require(IUser(DBContract(DB_CONTRACT).USER_INFO()).isValidUser(_msgSender()),'invalid user.');
        require(_t >= 300_000 && _t < 400_000 && _n > 0 && _n < 4,'unsupported');
        require(!nameUsed[_name] && !_isReverseName(_name) && !_nodeMinted[_msgSender()] ,'used');
        address _pm = DBContract(DB_CONTRACT).USDT_TOKEN();
        //status
        nameUsed[_name] = true;
        //_nodeMinted[_msgSender()] = true;
        _isNodeNft[_t] = _n;
        _userNodeNft[_msgSender()] = _n;
        uint256[] memory nf = DBContract(DB_CONTRACT).nodeByIndex(_n-1);
        uint256 mp = nf[0] * (10 ** IERC20MetadataUpgradeable(_pm).decimals());
        //mint
        _pay(_pm, _msgSender(), mp, IUser.REV_TYPE.MINT_NFT_ADDR);
        (uint256 v, uint256 i) = _attributesGen(_msgSender());
        nftInfo[_t] = [nf[1], v, i, 0];
        ERC721Upgradeable._safeMint(_msgSender(), _t);
        emit Mint(_t, nftInfo[_t], string(abi.encodePacked(_name, ".lynk")), _pm, mp);
        emit NodeMint(_msgSender(),_t,mp,_n);
        INode(DBContract(DB_CONTRACT).USER_INFO()).nodeReward(_msgSender(),nf[2],nf[3],nf[1]);
    }    
}

