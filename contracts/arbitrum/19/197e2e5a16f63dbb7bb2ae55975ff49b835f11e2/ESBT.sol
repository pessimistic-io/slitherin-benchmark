// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/utils/Counters.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./IERC721Metadata.sol";
import "./ERC721Enumerable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./ERC165.sol";
import "./ReentrancyGuard.sol";
import "./IESBT.sol";
import "./DataStore.sol";
import "./INFTUtils.sol";


interface IAcitivity {
    function updateCompleteness(address _account) external returns (bool);
    function balanceOf(address _account) external view returns (uint256);
}


contract ESBT is ReentrancyGuard, Ownable, IERC721, IERC721Metadata, IESBT, DataStore{
    using SafeMath for uint256;
    using Strings for uint256;
    using Address for address;

    string internal _baseImgURI;// Base token URI
    string internal _name = "EDE Soul Bound Token";// 

    bytes32 public constant REFERRAL_PARRENT = keccak256("REFERRAL_PARRENT");
    bytes32 public constant REFERRAL_CHILD = keccak256("REFERRAL_CHILD");
    bytes32 public constant ACCUM_POSITIONSIZE = keccak256("ACCUM_POSITIONSIZE");
    bytes32 public constant ACCUM_SWAP = keccak256("ACCUM_SWAP");
    bytes32 public constant ACCUM_ADDLIQUIDITY = keccak256("ACCUM_ADDLIQUIDITY");
    bytes32 public constant ACCUM_SCORE = keccak256("ACCUM_SCORE");
    bytes32 public constant TIME_SOCRE_DEC= keccak256("TIME_SOCRE_DEC");
    bytes32 public constant TIME_RANK_UPD = keccak256("TIME_RANK_UPD");

    bytes32 public constant VALID_VAULTS = keccak256("VALID_VAULTS");
    bytes32 public constant VALID_LOGGER = keccak256("VALID_LOGGER");
    bytes32 public constant VALID_SCORE_UPDATER = keccak256("VALID_SCORE_UPDATER");
    bytes32 public constant ACCUM_FEE_DISCOUNTED = keccak256("ACCUM_FEE_DISCOUNTED");
    bytes32 public constant ACCUM_FEE_REBATED = keccak256("ACCUM_FEE_REBATED");
    bytes32 public constant ACCUM_FEE_REBATED_CLAIMED = keccak256("ACCUM_FEE_REBATED_CLAIMED");
    bytes32 public constant ACCUM_FEE_DISCOUNTED_CLAIMED = keccak256("ACCUM_FEE_DISCOUNTED_CLAIMED");
    bytes32 public constant ACCUM_FEE = keccak256("ACCUM_FEE");
    bytes32 public constant MIN_MINT_TRADING_VALUE = keccak256("MIN_MINT_TRADING_VALUE");
    bytes32 public constant INTERVAL_RANK_UPDATE = keccak256("INTERVAL_RANK_UPDATE");
    bytes32 public constant INTERVAL_SCORE_UPDATE = keccak256("INTERVAL_SCORE_UPDATE");
    bytes32 public constant ONLINE_ACTIVITIE = keccak256("ONLINE_ACTIVITIE");
   
    uint256 public constant FEE_PERCENT_PRECISION = 10 ** 6;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant SCORE_PRECISION = 10 ** 18;
    uint256 public constant USD_TO_SCORE_PRECISION = 10 ** 12;
    uint256 public constant SCORE_DECREASE_PRECISION = 10 ** 18;

    uint256 public scoreDecreasePercentPerDay;

    event ScoreUpdate(address _account, address _fromAccount, uint256 _addition, uint256 _reasonCode);
    event ScoreDecrease(address _account, uint256 _amount, uint256 _timegap);
    event RankUpdate(address _account, uint256 _rankP, uint256 _rankA);
    event UpdateFee(address _account, uint256 _origFee, uint256 _discountedFee, address _parent, uint256 _rebateFee);

    mapping(address => uint256) private _balances;
    mapping(address => bytes32) public loggerDef;
    mapping(uint256 => uint256) public override scorePara;
    uint256[] public scoreToRank;
    uint256[] public rankToReb;
    uint256[] public rankToDis;

    address public gEDE;
    struct ESBTStr {
        address owner;
        string nickName;
        string refCode;
        uint256 createTime;
        uint256 rank;
    }
    ESBTStr[] private _tokens;// 
    mapping(address => uint256) public override addressToTokenID;
    mapping(string => address) public refCodeOwner;
   
    INFTUtils NFTUtils;

    constructor( address _NFTUtils) {
        require(_NFTUtils != address(0), "empty NFTUtils address");
        NFTUtils = INFTUtils(_NFTUtils);
        uint256 cur_time = block.timestamp;
        string memory defRC =  NFTUtils.genReferralCode(0);
        if (refCodeOwner[defRC]!= address(0))
            defRC = string(abi.encodePacked(defRC, cur_time));
        ESBTStr memory _ESBTStr = ESBTStr(address(this), "ESBT OFFICIAL", defRC, cur_time, 1);
        _tokens.push(_ESBTStr);
        addressToTokenID[address(this)] = 0;
        refCodeOwner[defRC] = address(this);
        _balances[address(this)] = 1;
        //set default:
        scorePara[1] = 20;//score_tradeOwn
        scorePara[2] = 4;//score_tradeOwn
        scorePara[3] = 15;//score_swapOwn
        scorePara[4] = 3;//score_swapChd
        scorePara[5] = 10;//score_addLiqOwn
        scorePara[6] = 2;//score_addLiqChd
        scorePara[8] = 2;//invite create Account
        scorePara[101] = 20;//score_tradeOwn
        scorePara[102] = 4;//score_tradeOwn
        scorePara[103] = 15;//score_swapOwn
        scorePara[104] = 3;//score_swapChd
        scorePara[105] = 10;//score_addLiqOwn
        scorePara[106] = 2;//score_addLiqChd
        scorePara[108] = 10;//invite create Account

        // scorePara[10000] = 0;//gEdeBalance for Rank E
        // scorePara[10001] = 0;//gEdeBalance for Rank D
        // scorePara[10002] = 0;//gEdeBalance for Rank C
        // scorePara[10003] = 0;//gEdeBalance for Rank B
        // scorePara[10004] = 1000 * 1e18;//gEdeBalance for Rank A
        scorePara[10005] = 5000 * 1e18;//gEdeBalance for Rank S
        scorePara[10006] = 10000 * 1e18;//gEdeBalance for Rank SS
    }

    modifier onlyScoreUpdater() {
        require(hasAddressSet(VALID_SCORE_UPDATER, msg.sender), "unauthorized updater");
        _;
    }

    ///--------------------- Owner setting
    function setScorePara(uint256 _id, uint256 _value) public onlyOwner {
        // require(_value < 1000, "invalid value");
        scorePara[_id] = _value;
    }

    function setNFTUtils(address _NFTUtils) public onlyOwner {
        NFTUtils = INFTUtils(_NFTUtils);
    }
    
    function setgEdeYieldDistributor(address _gEDE) public onlyOwner {
        gEDE = _gEDE;
    }

    function setUintValue(bytes32 _bIdx, uint256 _value) public onlyOwner {
        setUint(_bIdx, _value);
    }
    function setUintValueByString(string memory _strIdx, uint256 _value) public onlyOwner {
        setUint(keccak256(abi.encodePacked(_strIdx)), _value);
    }

    function setAcitvity(address _act, bool _add) public onlyOwner {
        if (_add )
            safeGrantAddressSet(ONLINE_ACTIVITIE, _act);
        else
            safeRevokeAddressSet(ONLINE_ACTIVITIE, _act);
    }

    function setAddVal(bytes32 _bIdx, address _add, uint256 _val) public onlyOwner {
        setAddUint(_add, _bIdx, _val);
    }

    function setScoreToRank(uint256[] memory _minValue) external onlyOwner{
        require(_minValue.length > 3 && _minValue[0] == 0, "invalid score-rank setting");
        scoreToRank = _minValue;
    }

    function setDisReb(uint256[] memory _dis, uint256[] memory _reb) external onlyOwner{
        require(scoreToRank.length +1 == _dis.length && _dis.length == _reb.length, "invalid dis-reb setting");
        rankToReb = _reb;
        rankToDis = _dis;
    }

    function setScorePlan(uint256 _decPerDay, uint256 _decInterval, uint256 _rankUpdInterval) external onlyOwner {
        require(_decPerDay < SCORE_DECREASE_PRECISION, "invalid Decreasefactor");
        scoreDecreasePercentPerDay = _decPerDay;       
        setUint(INTERVAL_SCORE_UPDATE, _decInterval);
        setUint(INTERVAL_RANK_UPDATE, _rankUpdInterval);
    }

    function setVault(address _vault, bool _status) external onlyOwner {
        if (_status){
            grantAddressSet(VALID_VAULTS, _vault);
            loggerDef[_vault] = keccak256(abi.encodePacked("VALID_LOGGER", _vault));
            _setLogger(_vault, true);
        }
        else{
            revokeAddressSet(VALID_VAULTS, _vault);
            _setLogger(_vault, false);
        }
    }

    function setScoreUpdater(address _updater, bool _status) external onlyOwner {
        if (_status){
            safeGrantAddressSet(VALID_SCORE_UPDATER, _updater);
            _setLogger(_updater, true);
        }
        else{
            safeRevokeAddressSet(VALID_SCORE_UPDATER, _updater);
            _setLogger(_updater, false);
        }
    }



    //================= ESBT creation =================
    function safeMint(string memory _refCode) external nonReentrant returns (string memory) {
        require(tx.origin == msg.sender && !msg.sender.isContract(), "onlyEOA");
        return _mint(msg.sender, _refCode, "ESBT User");
    }

    function mintWithName(string memory _refCode, string memory _nickName) external nonReentrant returns (string memory) {
        require(tx.origin == msg.sender && !msg.sender.isContract(), "onlyEOA");
        return _mint(msg.sender, _refCode, _nickName);
    }

    function mintDefault( ) external nonReentrant returns (string memory) {
        require(tx.origin == msg.sender && !msg.sender.isContract(), "onlyEOA");
        return _mint(msg.sender, defaultRefCode(), "DefaultName");
    }

    function _mint(address _newAccount, string memory _refCode, string memory _nickName) internal returns (string memory) {
        require(balanceOf(_newAccount) == 0, "already minted.");
        require(userSizeSum(_newAccount) >= getUint(MIN_MINT_TRADING_VALUE), "Min. trading value not satisfied.");
        address _referalAccount = refCodeOwner[_refCode];
        require(_referalAccount != address(0) && balanceOf(_referalAccount) > 0, "Invalid referal Code");
        uint256 _tId = _tokens.length;
        uint256 cur_time = block.timestamp;

        setAddUint(_newAccount, TIME_RANK_UPD, block.timestamp);
        uint256 new_rank = rankByScore(getAddUint(_newAccount, ACCUM_SCORE), getUsergEdeBalance(_newAccount));
        emit RankUpdate(_newAccount, _tokens[addressToTokenID[_newAccount]].rank, new_rank);

        _balances[_newAccount] += 1;
        string memory refC =  NFTUtils.genReferralCode(_tId);
        ESBTStr memory _ESBTStr = ESBTStr(address(this), _nickName, refC, cur_time, new_rank);
        _tokens.push(_ESBTStr);
        addressToTokenID[_newAccount] = _tId;
        refCodeOwner[refC] = _newAccount;
        grantAddMpAddressSetForAccount(_newAccount, REFERRAL_PARRENT, _referalAccount);
        updateReferralForAccount(_newAccount, _referalAccount);
        updateScore(_referalAccount, _newAccount, scorePara[8] * SCORE_PRECISION, 0);
        if (getAddressSetCount(ONLINE_ACTIVITIE) > 0){
            address[] memory actList = getAddressSetRoles(ONLINE_ACTIVITIE, 0, getAddressSetCount(ONLINE_ACTIVITIE));
            for(uint i = 0; i < actList.length; i++){
                IAcitivity(actList[i]).updateCompleteness(_newAccount);
                IAcitivity(actList[i]).updateCompleteness(_referalAccount);
            }
        }
        return refC;        
    }

    function setNickName(string memory _setNN) external {
        address _account = msg.sender;
        require(balanceOf(_account) == 1, "invald holder");
        _tokens[addressToTokenID[_account]].nickName = _setNN;
    }

    function updateUserRS(address _account) external {
        updateScore(_account, _account, 0, 999);
    }

    function getUsergEdeBalance(address _account) public view returns (uint256){
        if (gEDE == address(0)) return 0;
        return IAcitivity(gEDE).balanceOf(_account);
    }

    function rankByScore(uint256 _score, uint256 _gEdeBalance) public view returns (uint256) {
        uint256 reqScore = _score.div(SCORE_PRECISION);
        uint256 _rankRes = scoreToRank.length;
        for(uint i = 1; i < scoreToRank.length; i++){
            if (reqScore >= scoreToRank[i-1] && reqScore < scoreToRank[i]){
                _rankRes = i;
                break;
            }
        }
        if (gEDE == address(0)) return _rankRes;
        
        //get max rank by gEdeBalance
        uint256 _gMaxRank = scoreToRank.length;
        for(uint256 i = 1; i < scoreToRank.length; i++){
            if (_gEdeBalance < scorePara[10000 + i]){
                _gMaxRank = i;
                break;
            }
        }
        return _rankRes > _gMaxRank ? _gMaxRank : _rankRes; 
    }



    function rankToDiscount(uint256 _rank) public view returns (uint256, uint256){
        return (rankToDis[_rank], rankToReb[_rank]);
    }

    function accountToDisReb(address _account) public override view returns (uint256, uint256){
        if (balanceOf(_account)!= 1) return (0,0);
        return rankToDiscount(_tokens[addressToTokenID[_account]].rank);
    }

    function rank(address _account) public override view returns (uint256){
        if (balanceOf(_account)!= 1) return 0;
        return _tokens[addressToTokenID[_account]].rank;
    }

    function updateFee(address _account, uint256 _origFee) external override returns (uint256){
        address _vault = msg.sender;
        _validLogger(_vault);
        if (!hasAddressSet(VALID_VAULTS, _vault)) return 0;
        if (balanceOf(_account)!= 1) return 0;

        (address[] memory _par, ) = getReferralForAccount(_account);
        if (_par.length != 1) return 0;
        (uint256 dis_per,  ) = accountToDisReb(_account);
        ( , uint256 reb_per) = accountToDisReb(_par[0]);

        uint256 _discountedFee = _origFee.mul(dis_per).div(FEE_PERCENT_PRECISION);
        uint256 _rebateFee = _origFee.mul(reb_per).div(FEE_PERCENT_PRECISION);
        if (_rebateFee.add(_discountedFee) >= _origFee){
            _rebateFee = 0;
            _discountedFee = 0;
        }
        incrementAddUint(_account, ACCUM_FEE_DISCOUNTED, _discountedFee);
        // incrementAddUint(_account, tradingKey[_vault][ACCUM_FEE], _origFee);
        address _parent = getAddMpAddressSetRoles(_account, REFERRAL_PARRENT, 0, 1)[0];
        incrementAddUint(_parent, ACCUM_FEE_REBATED, _rebateFee);//tradingKey[_vault][ACCUM_FEE_REBATED]
        emit UpdateFee(_account, _origFee, _discountedFee, _parent, _rebateFee);
        return _discountedFee.add(_rebateFee);
    }

    function updateClaimVal(address _account) external onlyScoreUpdater override {
        setAddUint(_account, ACCUM_FEE_REBATED_CLAIMED,  getAddUint(_account, ACCUM_FEE_REBATED));
        setAddUint(_account, ACCUM_FEE_DISCOUNTED_CLAIMED,  getAddUint(_account, ACCUM_FEE_DISCOUNTED));
    }

    function updateScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _reasonCode) external onlyScoreUpdater override {
        (address[] memory _par, ) = getReferralForAccount(_account);
        updateScore(_account, _account, _amount.div(1000).mul(scorePara[_reasonCode]).div(USD_TO_SCORE_PRECISION),_reasonCode);
        if (_par.length == 1)
            updateScore(_par[0], _account, _amount.div(1000).mul(scorePara[1000 + _reasonCode]).div(USD_TO_SCORE_PRECISION), 1000 + _reasonCode);
    }

    function updateTradingScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _refCode) external onlyScoreUpdater override {
        (address[] memory _par, ) = getReferralForAccount(_account);
        incrementAddUint(_account, ACCUM_POSITIONSIZE, _amount);
        updateScore(_account, _account, _amount.div(1000).mul(scorePara[1 + _refCode]).div(USD_TO_SCORE_PRECISION), 1 + _refCode);
        if (_par.length == 1)
            updateScore(_par[0], _account, _amount.div(1000).mul(scorePara[2 + _refCode]).div(USD_TO_SCORE_PRECISION), 11 + _refCode);
    }

    function updateSwapScoreForAccount(address _account, address /*_vault*/, uint256 _amount) external onlyScoreUpdater override{
        (address[] memory _par,  ) = getReferralForAccount(_account);
        incrementAddUint(_account, ACCUM_SWAP, _amount);
        updateScore(_account, _account, _amount.div(1000).mul(scorePara[3]).div(USD_TO_SCORE_PRECISION), 2);
        if (_par.length == 1)
            updateScore(_par[0], _account, _amount.div(1000).mul(scorePara[4]).div(USD_TO_SCORE_PRECISION), 12);
    }

    function updateAddLiqScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _refCode) external onlyScoreUpdater override {
        (address[] memory _par,  ) = getReferralForAccount(_account);
        incrementAddUint(_account, ACCUM_ADDLIQUIDITY, _amount);
        updateScore(_account,  _account, _amount.div(1000).mul(scorePara[5 + _refCode]).div(USD_TO_SCORE_PRECISION), 3 + _refCode);
        if (_par.length == 1)
            updateScore(_par[0], _account, _amount.div(1000).mul(scorePara[6 + _refCode]).div(USD_TO_SCORE_PRECISION), 13 + _refCode);
    }

    function updateScore(address _account, address _fromAccount, uint256 _amount, uint256 _reasonCode) private {
        uint256 prevTime = getAddUint(_account, TIME_SOCRE_DEC);
        uint256 timeError = block.timestamp.sub(prevTime);
        uint256 cur_score = getAddUint(_account, ACCUM_SCORE);
        if (timeError > getUint(INTERVAL_SCORE_UPDATE)){
            setAddUint(_account, TIME_SOCRE_DEC, block.timestamp);
            uint256 decreaseAmount = cur_score.mul(timeError.div(24 * 3600).mul(scoreDecreasePercentPerDay)).div(SCORE_DECREASE_PRECISION);
            decrementAddUint(_account, ACCUM_SCORE, decreaseAmount);
            emit ScoreDecrease(_account, decreaseAmount, timeError);
        }
        incrementAddUint(_account, ACCUM_SCORE, _amount);
        emit ScoreUpdate(_account, _fromAccount, _amount, _reasonCode);

        prevTime = getAddUint(_account, TIME_RANK_UPD);
        timeError = block.timestamp.sub(prevTime);
        if (timeError > getUint(INTERVAL_RANK_UPDATE) && balanceOf(_account) == 1){
            setAddUint(_account, TIME_RANK_UPD, block.timestamp);
            uint256 new_rank = rankByScore(getAddUint(_account, ACCUM_SCORE), getUsergEdeBalance(_account));
            emit RankUpdate(_account, _tokens[addressToTokenID[_account]].rank, new_rank);
            _tokens[addressToTokenID[_account]].rank = new_rank;
        }
    }


    //================= Internal Functions =================
    function _setLogger(address _account, bool _status) internal {
        if (_status && !hasAddressSet(loggerDef[_account], _account))
            grantAddressSet(loggerDef[_account],  _account);
        else if (!_status && hasAddressSet(loggerDef[_account], _account))
            revokeAddressSet(loggerDef[_account],  _account);
    }

    function _validLogger(address _account) internal view {
        require(hasAddressSet(loggerDef[_account], _account), "invalid logger");
    }

    function updateReferralForAccount(address _account_child, address _account_parrent) internal {
        require(getAddMpBytes32SetCount(_account_child, REFERRAL_PARRENT) == 0, "Parrent already been set");
        require(!hasAddMpAddressSet(_account_parrent, REFERRAL_CHILD, _account_child), "Child already exist");
        grantAddMpAddressSetForAccount(_account_parrent, REFERRAL_CHILD, _account_child);
        grantAddMpAddressSetForAccount(_account_child, REFERRAL_PARRENT, _account_parrent);
    }

    //=================Public data reading =================
    function getReferralForAccount(address _account) public override view returns (address[] memory , address[] memory){
        uint256 childNum = getAddMpAddressSetCount(_account, REFERRAL_CHILD);
        return (getAddMpAddressSetRoles(_account, REFERRAL_PARRENT, 0, 1),
                getAddMpAddressSetRoles(_account, REFERRAL_CHILD, 0, childNum));
    }

    function getESBTAddMpUintetRoles(address _mpaddress, bytes32 _key) public override view returns (uint256[] memory) {
        return getAddMpUintetRoles(_mpaddress, _key, 0, getAddMpUintSetCount(_mpaddress, _key));
    }
    
    function userSizeSum(address _account) public override view returns (uint256){
        return getAddUint(_account, ACCUM_POSITIONSIZE).add(getAddUint(_account, ACCUM_SWAP)).add(getAddUint(_account, ACCUM_ADDLIQUIDITY));
    }

    function userClaimable(address _account) public override view returns (uint256, uint256){
        return (getAddUint(_account, ACCUM_FEE_REBATED).sub(getAddUint(_account, ACCUM_FEE_REBATED_CLAIMED)),
                getAddUint(_account, ACCUM_FEE_DISCOUNTED).sub(getAddUint(_account, ACCUM_FEE_DISCOUNTED_CLAIMED)));
    }

    function getScore(address _account) external override view returns (uint256) {
        uint256 prevTime = getAddUint(_account, TIME_SOCRE_DEC);
        uint256 timeError = block.timestamp.sub(prevTime);
        uint256 cur_score = getAddUint(_account, ACCUM_SCORE);
        if (timeError < getUint(INTERVAL_SCORE_UPDATE)) return cur_score;
        uint256 pastDays = timeError.div(24 * 3600);
        uint256 decreaseAmount = cur_score.mul(pastDays.mul(scoreDecreasePercentPerDay)).div(SCORE_DECREASE_PRECISION);
        return cur_score > decreaseAmount ? cur_score.sub(decreaseAmount) : 0;
    }

    function getRefCode(address _account) public override view returns (string memory) {
        if (_account == address(this)) return _tokens[0].refCode;
        if (balanceOf(_account) != 1) return "";
        return _tokens[addressToTokenID[_account]].refCode;
    }

    function defaultRefCode() public view returns (string memory){
        return _tokens[0].refCode;//
    }

    function createTime(address _account) public override view returns (uint256){
        if (balanceOf(_account) != 1) return 0;
        return _tokens[addressToTokenID[_account]].createTime;
    }
    
    function nickName(address _account) public override view returns (string memory){
        if (balanceOf(_account) != 1) return "";
        return _tokens[addressToTokenID[_account]].nickName;
    }

    //=================ERC 721 override=================
    function name() public view virtual override returns (string memory) {
        return "EDETrade SoulBoundToken";
    }

    function symbol() public view virtual override returns (string memory) {
        return "ESBT";
    }

    function approve(address /*to*/, uint256 /*tokenId*/) public pure override {
        require(false, "SBT: No approve method");
    }

    function getApproved(uint256 /*tokenId*/) public pure override returns (address) {
        return address(0);
    }

    function setApprovalForAll(address /*operator*/, bool /*approved*/) public pure override {
        require(false, "SBT: no approve all");
    }

    function isApprovedForAll(address /*owner*/, address /*operator*/) public pure override returns (bool) {
        return false;
    }

    function balanceOf(address owner) public view override returns (uint256) {
        require(
            owner != address(0),
            "ERC721: balance query for the zero address"
        );
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        require(
            _exists(tokenId),
            "ERC721: owner query for nonexistent token"
        );
        return address(_tokens[tokenId].owner);
    }

    function isOwnerOf(address account, uint256 id) public view returns (bool) {
        address owner = ownerOf(id);
        return owner == account;
    }

    function transferFrom(
        address /*from*/,
        address /*to*/,
        uint256 /*tokenId*/
    ) public pure override {
        require(false, "SoulBoundToken: transfer is not allowed");
    }


    function safeTransferFrom(
        address /*from*/,
        address /*to*/,
        uint256 /*tokenId*/
    ) public  pure override {
        require( false, "SoulBoundToken: transfer is not allowed");
    }

    function safeTransferFrom(
        address /*from*/,
        address /*to*/,
        uint256 /*tokenId*/,
        bytes memory /*_data*/
    ) public pure override {
        require( false, "SoulBoundToken: transfer is not allowed");
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        if (tokenId >= _tokens.length) return false;
        if (_tokens[tokenId].createTime < 1) return false;
        return true;
    }


    /* ============ Util Functions ============ */
    function setURI(string calldata newURI) external onlyOwner {
        _baseImgURI = newURI;
    }

    function compileAttributes(uint256 tokenId) internal view returns (string memory) {
        address _account = ownerOf(tokenId);
        return  string(
                abi.encodePacked(
                    "[",
                    NFTUtils.attributeForTypeAndValue(
                        "Name",
                        nickName(_account)
                    ),
                    NFTUtils.attributeForTypeAndValue(
                        "Rank",
                        Strings.toString(rank(_account))
                    ),
                    ",",
                    NFTUtils.attributeForTypeAndValue(
                        "ReferalCode",
                        _tokens[tokenId].refCode
                    ),
                    "]"
                )
            );
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "FTeamNFT: FTeamNFT does not exist");
        string memory metadata = string(
            abi.encodePacked(
                '{"name": "',
                _name,
                ' #',
                tokenId.toString(),
                '", "description": "EDE Soul Bound Token", "image": "',
                _baseImgURI,
                tokenId.toString(),
                '.jpg", "attributes":',
                compileAttributes(tokenId),
                "}"
            )
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    NFTUtils.base64(bytes(metadata))
                )
            );
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool){
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId;
    }
}



