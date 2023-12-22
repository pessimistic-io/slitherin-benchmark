pragma solidity 0.6.6; 

import "./WokenPair.sol";
import "./Timekeeper.sol";

contract WokenFactory is Timekeeper {

    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(WokenPair).creationCode));
    address public feeTo;
    address public feeToSetter;
    address public dexAdmin;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    mapping(address => bool) public isTimekeeperEnabledLP;
    mapping(address => bool) public isTimekeeperEnabledLPProposal;
    mapping(address => address) public pairAdmin;
    mapping(address => address) public pairAdminDao;
    mapping(address => bool ) public moderators;
    mapping(address => address) public roleRequests;
    mapping(address => uint256) private timelock;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    event TimekeeperEnable(address indexed pair);
    event TimekeeperEnableProposal(address indexed pair, bool enable);
    event DexAdminChanged(address oldAdmin, address newAdmin);
    event PairAdminChanged(address indexed oldPairAdmin, address indexed newPairAdmin);
    event TimekeeperProposal(address indexed pair);
    event TimekeeperChange(address indexed pair);
    event ForceOpenTimelock(address indexed pair, bool isOpen);
    event ForceOpen(address indexed pair);
    event ModeratorChanged(address moderator, bool isModerator);
    event RolePairAdminRequested(address indexed pair, address indexed pairAdminAddr);
    event RolePairAdminDaoRequested(address indexed pair, address indexed pairAdminDaoAddr);
    event RolePairAdminApproved(address indexed pair, address indexed newPairAdmin);
    event RolePairAdminDaoApproved(address indexed pair, address indexed newPairAdminDao);
    event SwapFeeChange(address indexed pair, uint32 newSwapFee, address indexed Pairadmin);


    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
        dexAdmin=msg.sender;
    }

    modifier isDexAdmin(){
        require(msg.sender==dexAdmin, "you are not the dex Admin");
        _;
    }

    modifier isPairAdmin(address _pair){
        require(pairAdmin[_pair]==msg.sender, "you are not the pair Admin");
        _;
    }

    modifier isPairAdminDao(address _pair){
        require (pairAdminDao[_pair]==msg.sender, "you are not the pair Admin DAO");
        _;
    }


    modifier isModerators(){
        require (moderators[msg.sender]==true, "you are not DAO Moderator");
        _;
    }

    modifier isDexOrModerators(){
        require (moderators[msg.sender]==true || dexAdmin==msg.sender, "you are not allowed to do so");
        _;
    }

    function isTradingOpen(address _pair) public view override returns (bool) {
          if  (isTKEnabled(_pair) == true){
            return Timekeeper.isTradingOpen(_pair);
        } else return true;
    }

    function getSwapFee(address _pair) public view returns (uint32) {
        return WokenPair(_pair).swapFee();
    }

    function isTKEnabled(address _addr) public view returns (bool){
        return isTimekeeperEnabledLP[_addr];
    }

    function getDaysOpenLP(address _addr) public view returns (uint8[7] memory){
        return TimekeeperPerLp[_addr].closedDays;
    }

    function getDaysOpenLPProposal(address _addr) public view returns (uint8[7] memory){
        return TimekeeperPerLpWaitingForApproval[_addr].closedDays;
    }

    function setDexAdmin(address _addr) public isDexAdmin{
        address temp = dexAdmin;
        dexAdmin = _addr;
        emit DexAdminChanged(temp, _addr);
    }
    
    function setPairAdmin(address _addr, address _pair) public isPairAdmin(_pair){
        address temp = pairAdmin[_pair];
        pairAdmin[_pair] = _addr;
        emit PairAdminChanged(temp, _addr);
    }

    function setPairAdminDao(address _addr, address _pair) public isPairAdminDao(_pair){
        address temp = pairAdminDao[_pair];
        pairAdminDao[_pair] = _addr;
        emit PairAdminChanged(temp, _addr);
    }

    function setModerator(address _addr, bool _moderator) public isDexAdmin{
        moderators[_addr] = _moderator;
        emit ModeratorChanged(_addr, _moderator);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'Woken: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Woken: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Woken: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(WokenPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        WokenPair(pair).initialize(token0, token1, address(this));
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        pairAdmin[pair]=tx.origin;
        TimekeeperPerLp[pair]= pairTimekeeper(0, 0, 23, 59, [0,0,0,0,0,1,1], 0, true);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setEnableProposal(address _pair, bool _enable) public isPairAdminDao(_pair)  {
        isTimekeeperEnabledLPProposal[_pair]=_enable;
        emit TimekeeperEnableProposal(_pair,_enable);
    }
 
   function setEnableDao(address _pair) public isDexOrModerators  {
        isTimekeeperEnabledLP[_pair]=isTimekeeperEnabledLPProposal[_pair];
        emit TimekeeperEnable(_pair);
    }


    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'Woken: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'Woken: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }


    function setTimeForPairDao(address _pair, uint8 openingHour, uint8 openingMinute, uint8 closingHour, uint8 closingMin, uint8[7] memory ClosedDays, int8 utcOffset, bool onlyDay) public isPairAdminDao(_pair)  {
        require (isTKEnabled(_pair), "You must Enable your Timekeeper to edit your Trading Hours");
        _setKeeperGlobal(_pair, openingHour, openingMinute , closingHour, closingMin, ClosedDays, utcOffset, onlyDay);
        emit TimekeeperProposal(_pair);
    } 
   
    // DAO : Dex Admin and Moderators approvals  
    function setTimekeeperFromProposal(address _pair) public isDexOrModerators{
        TimekeeperPerLp[_pair]=TimekeeperPerLpWaitingForApproval[_pair];
        delete TimekeeperPerLpWaitingForApproval[_pair];
        emit TimekeeperChange(_pair);
    }

    function refuseProposal(address _pair) public isDexOrModerators{
        delete TimekeeperPerLpWaitingForApproval[_pair];
        emit TimekeeperProposal(_pair);
    }

    // for Pair Admin 
    function setTimeForPair(address _pair, uint8 openingHour, uint8 openingMinute, uint8 closingHour, uint8 closingMin, uint8[7] memory ClosedDays, int8 utcOffset, bool onlyDay) public isPairAdmin(_pair)  {
        require (isTKEnabled(_pair), "You must Enable your Timekeeper to edit your Trading Hours");
        _setKeeperGlobal(_pair, openingHour, openingMinute , closingHour, closingMin, ClosedDays, utcOffset, onlyDay);
        TimekeeperPerLp[_pair]=TimekeeperPerLpWaitingForApproval[_pair];
        delete TimekeeperPerLpWaitingForApproval[_pair];
        emit TimekeeperChange(_pair);
        
    }
    function setEnable(address _pair, bool _enable) public isPairAdmin(_pair) {
        isTimekeeperEnabledLP[_pair] = _enable;
        emit TimekeeperEnable(_pair);
    }   
    

    // Role Request
     function requestPairAdminDao(address _pair) public isPairAdmin(_pair) {
        require(roleRequests[_pair] == address(0), "Role Request already done");
        roleRequests[_pair] = msg.sender; 
        emit RolePairAdminDaoRequested(_pair, msg.sender);
    }

    function requestPairAdmin(address _pair) public isPairAdminDao(_pair) {
        require(roleRequests[_pair] == address(0), "Role Request already done");
        roleRequests[_pair] = msg.sender; 
        emit RolePairAdminRequested(_pair, msg.sender);
    }

    function approvePairAdminDao(address _pair) public isDexAdmin {
        address requester = roleRequests[_pair];
        require(requester != address(0), "No pending request for this pair");
        require(pairAdmin[_pair] == requester, "Only the current PairAdmin can be approved as PairAdminDao");
    
        pairAdminDao[_pair] = requester; 
        pairAdmin[_pair] = address(0); 
        roleRequests[_pair] = address(0); 
        emit RolePairAdminDaoApproved(_pair, msg.sender);
    }

    function approvePairAdmin(address _pair) public isDexAdmin {
        address requester = roleRequests[_pair];
        require(requester != address(0), "No pending request for this pair");
        require(pairAdminDao[_pair] == requester, "Only the current PairAdminDao can be approved as PairAdmin");
    
        pairAdmin[_pair] = requester; 
        pairAdminDao[_pair] = address(0); 
        roleRequests[_pair] = address(0); 
        emit RolePairAdminApproved(_pair, msg.sender);
    }

    function refuseRole(address _pair) public isDexAdmin {
        delete roleRequests[_pair];
    }

    //setSwapFee
    function setSwapFee(address _pair, uint32 _swapFee) external isPairAdminDao(_pair) {
        WokenPair(_pair).setSwapFee(_swapFee);
        emit SwapFeeChange(_pair, _swapFee, msg.sender);
    }

    //security option for DexAdmin to avoid closed pair for lifetime
    function setForceOpenTimelock(address _pair, bool _enable) public isDexAdmin {
        require (isTKEnabled(_pair), "Timekeeper is Disabled, market is already open");
        timelock[_pair] = block.timestamp + 172800; // 48h timelock
        isForceOpenTimelock[_pair] = _enable;
        emit ForceOpenTimelock(_pair, _enable);
    }

    function setForceOpen(address _pair) public isDexAdmin {
        require(block.timestamp >= timelock[_pair], "Timelock not yet expired");
        isForceOpen[_pair] = isForceOpenTimelock[_pair];
        emit ForceOpen(_pair);
    }
}

