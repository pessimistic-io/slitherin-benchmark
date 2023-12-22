// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./AssetTransfer.sol";
import "./SignatureLens.sol";

contract TicketLottery is SignatureLens,ReentrancyGuard{
    using SafeMath for uint256;

    enum Item{
        FIRST_PRIZE,
        SECOND_PRIZE,
        THIRD_PRIZE,
        NFT_DIVIDEND,
        PLATFORM_RAKE,
        REPO_DESTROY
    }

    uint[] private _itemRates = [20,10,5,10,5,50];
    uint private _fee;
    address private _feeTo;
    address private _repoTo;
    address private _dividendNft;
    address private _rewardCoin;

    uint private _totalReceivedJackpot;
    uint private _totalClaimedJackpot;

    mapping(uint => uint) private _phaseReceivedJackpot;
    mapping(address => uint) private _userClaimedJackpot;
    mapping(uint => mapping(address=>mapping(uint =>uint))) private _phaseUserItemClaimedJackpot;
    mapping(uint => mapping(address => uint[])) private _phaseUserLuckyNos;
    mapping(uint => mapping(uint => address)) private _phaseLuckyNoUser;
    mapping(uint => uint[]) private _phaseLuckyNos;
    mapping(uint => uint[]) private _phaseLotteryLuckyNos;


    event PaymentReceived(address indexed sender,uint amount);
    event ResetFee(address indexed operator, uint oldFee, uint newFee);
    event ResetFeeTo(address indexed operator, address indexed oldFeeTo, address indexed newFeeTo);
    event ResetRepoTo(address indexed operator, address indexed oldRepoTo, address indexed newRepoTo);
    event ResetDividendNft(address indexed operator, address indexed oldDividendNft, address indexed newDividendNft);
    event WithdrawAsset(address indexed operator, address indexed asset, address indexed receiver, uint amount);
    event BatchSale(uint phase, address indexed operator, uint count, bytes s);
    event ClaimPrizeRewards(address indexed operator, uint phase, uint amount);
    event ClaimShareRewards(address indexed operator, uint amount, bytes s);
    event ClaimPurchaseRewards(address indexed operator, uint amount, bytes s);
    event ClaimInviteRewards(address indexed operator, uint amount, bytes s);

    constructor(address feeTo
        , address repoTo
        , address dividendNft
        , address rewardCoin
        , address singer
        , uint fee) SignatureLens(singer){
        require(feeTo != address(0)
            && repoTo != address(0)
            && dividendNft != address(0), "Parameter error");
        _feeTo = feeTo;
        _repoTo = repoTo;
        _dividendNft = dividendNft;
        _rewardCoin = rewardCoin;
        _fee = fee;
    }

    function resetFee(uint fee) public onlyOwner{
        uint oldFee = _fee;
        _fee = fee;
        emit ResetFee(_msgSender(), oldFee, fee);
    }

    function resetFeeTo(address feeTo) public onlyOwner{
        address oldFeeTo = _feeTo;
        _feeTo = feeTo;
        emit ResetFeeTo(_msgSender(), oldFeeTo, feeTo);
    }

    function resetRepoTo(address repoTo) public onlyOwner{
        address oldRepoTo = _repoTo;
        _repoTo = repoTo;
        emit ResetRepoTo(_msgSender(), oldRepoTo, repoTo);
    }

    function resetDividendNft(address dividendNft) public onlyOwner{
        address oldDividendNft = _dividendNft;
        _dividendNft = dividendNft;
        emit ResetDividendNft(_msgSender(), oldDividendNft, dividendNft);
    }

    function fee() public view returns(uint){
        return _fee;
    }

    function feeTo() public view returns(address){
        return _feeTo;
    }

    function repoTo() public view returns(address){
        return _repoTo;
    }

    function dividendNft() public view returns(address){
        return _dividendNft;
    }

    function rewardCoin() public view returns(address){
        return _rewardCoin;
    }

    function totalReceivedJackpot() public view returns(uint){
        return _totalReceivedJackpot;
    }

    function totalClaimedJackpot() public view returns(uint){
        return _totalClaimedJackpot;
    }

    function itemRatesLength() public view returns(uint){
        return _itemRates.length;
    }

    function itemRates(uint index) public view returns(uint){
        return _itemRates[index];
    }

    function phaseUserLuckyNosLength(uint phase, address user) public view returns(uint){
        return _phaseUserLuckyNos[phase][user].length;
    }

    function phaseUserLuckyNo(uint phase, address user, uint index) public view returns(uint){
        return _phaseUserLuckyNos[phase][user][index];
    }

    function phaseLuckyNoUser(uint phase, uint luckNo) public view returns(address){
        return _phaseLuckyNoUser[phase][luckNo];
    }

    function phaseLotteryLuckyNosLength(uint phase) public view returns(uint){
        return _phaseLotteryLuckyNos[phase].length;
    }

    function phaseLuckyNosLength(uint phase) public view returns(uint){
        return _phaseLuckyNos[phase].length;
    }

    function phaseLuckyNo(uint phase,uint index) public view returns(uint){
        return _phaseLuckyNos[phase][index];
    }

    function phaseLotteryLuckyNo(uint phase,uint index) public view returns(uint){
        return _phaseLotteryLuckyNos[phase][index];
    }

    function phaseReceivedJackpot(uint phase) public view returns(uint){
        return _phaseReceivedJackpot[phase];
    }

    function phaseUserItemClaimedJackpot(uint phase, address user, Item item) public view returns(uint){
        return _phaseUserItemClaimedJackpot[phase][user][uint(item)];
    }

    function batchSale(uint phase, uint[] calldata luckyNos, Signature calldata signature) external payable nonReentrant{
        uint count = luckyNos.length;
        require(count >0, "The lucky number is empty");
        uint cost = fee().mul(count);
        require(msg.value >= cost, "The ether value sent is not correct");
        require(!isLottery(phase), "Prizes have been drawn");

        bytes32 params = keccak256(abi.encodePacked(phase, luckyNos));
        require(verifySignature("BatchSale(uint,uint[],Signature)", params, signature), "Illegal operation");


        uint[] storage _luckyNos = _phaseLuckyNos[phase];
        uint[] storage _userLuckyNos = _phaseUserLuckyNos[phase][msg.sender];
        for(uint i=0; i< luckyNos.length; i++){
            uint luckyNo = luckyNos[i];
            require(phaseLuckyNoUser(phase,luckyNo) == address(0),"Lucky numbers have been taken");

            _luckyNos.push(luckyNo);
            _userLuckyNos.push(luckyNo);
            _phaseLuckyNoUser[phase][luckyNo] = msg.sender;
        }
        _phaseReceivedJackpot[phase] = _phaseReceivedJackpot[phase].add(cost);
        _totalReceivedJackpot = _totalReceivedJackpot.add(cost);


        AssetTransfer.cost(msg.sender, address(this), address(0), msg.value);

        emit BatchSale(phase, msg.sender, count, signature.s);
    }

    function lottery(uint phase, uint[] calldata lotteryLuckyNos) external onlyOwner{
        require(lotteryLuckyNos.length == 3, "Wrong number of lucky numbers");
        require(!isLottery(phase), "Prizes have been drawn");

        uint[] storage _lotteryLuckyNos = _phaseLotteryLuckyNos[phase];
        for(uint i=0; i< lotteryLuckyNos.length; i++){
            _lotteryLuckyNos.push(lotteryLuckyNos[i]);
        }

        uint platformRakeRewards = getPhaseItemRewards(phase, Item.PLATFORM_RAKE);
        _lotteryTransfer(phase, Item.PLATFORM_RAKE, feeTo(), platformRakeRewards);
        uint repoDestroyRewards = getPhaseItemRewards(phase, Item.REPO_DESTROY);
        _lotteryTransfer(phase, Item.REPO_DESTROY, repoTo(), repoDestroyRewards);
    }

    function _lotteryTransfer(address to, uint rewards) internal{
        if(rewards == 0){
            return ;
        }
        _userClaimedJackpot[to] = _userClaimedJackpot[to].add(rewards);
        _totalClaimedJackpot = _totalClaimedJackpot.add(rewards);

        AssetTransfer.reward(address(this), to, address(0), rewards);
    }

    function _lotteryTransfer(uint phase, Item item, address to, uint rewards) internal{
        _lotteryTransfer(to,rewards);
        _phaseUserItemClaimedJackpot[phase][to][uint(item)] = rewards;
    }


    function isLottery(uint phase) public view returns(bool){
        return _phaseLotteryLuckyNos[phase].length > 0;
    }

    function isUserLottery(uint phase, address user) public view returns(bool){
        bool[] memory lotteryResults = getUserLotteryResults(phase,user);
        for(uint i=0; i< lotteryResults.length; i++){
            if(lotteryResults[i]){
                return true;
            }
        }
        return false;
    }

    function getUserLotteryResults(uint phase, address user) public view returns(bool[] memory){
        bool[] memory lotteryResults = new bool[](3);
        if(!isLottery(phase)){
            return lotteryResults;
        }

        uint[] memory _lotteryLuckyNos = _phaseLotteryLuckyNos[phase];
        for(uint i=0; i< _lotteryLuckyNos.length; i++){
            uint _lotteryLuckyNo = _lotteryLuckyNos[i];
            lotteryResults[i] = (user == phaseLuckyNoUser(phase, _lotteryLuckyNo));
        }
        return lotteryResults;
    }

    function claimPrizeRewards(uint phase) public nonReentrant{
        bool[] memory results = getUserLotteryResults(phase,msg.sender);
        uint totalRewards = 0;
        for(uint i=0; i< results.length; i++){
            if(!results[i]){
                continue;
            }

            require(phaseUserItemClaimedJackpot(phase,msg.sender,Item(i)) == 0,"Reward claimed");
            uint itemRewards = getPhaseItemRewards(phase, Item(i));
            totalRewards = totalRewards.add(itemRewards);

            _phaseUserItemClaimedJackpot[phase][msg.sender][i] = itemRewards;
        }

        if(totalRewards == 0){
            revert("TicketLottery: Losing lottery");
        }

        _lotteryTransfer(msg.sender,totalRewards);

        emit ClaimPrizeRewards(msg.sender, phase, totalRewards);
    }

    function claimShareRewards(uint amount, Signature calldata signature) public nonReentrant{
        bytes32 params = keccak256(abi.encodePacked(amount));
        require(verifySignature("ClaimShareRewards(uint,Signature)", params, signature), "Illegal operation");
        _lotteryTransfer(msg.sender, amount);


        emit ClaimShareRewards(msg.sender, amount, signature.s);
    }

    function claimPurchaseRewards(uint amount, Signature calldata signature) public nonReentrant{
        address to = msg.sender;
        bytes32 params = keccak256(abi.encodePacked(amount));
        require(verifySignature("ClaimPurchaseRewards(uint,Signature)", params, signature), "Illegal operation");
        AssetTransfer.reward(address(this), to, rewardCoin(), amount);

        emit ClaimPurchaseRewards(msg.sender, amount, signature.s);
    }

    function claimInviteRewards(uint amount, Signature calldata signature) public nonReentrant{
        address to = msg.sender;
        require(IERC721(dividendNft()).balanceOf(to) >0, "No NFT held");
        bytes32 params = keccak256(abi.encodePacked(amount));
        require(verifySignature("ClaimInviteRewards(uint,Signature)", params, signature), "Illegal operation");
        AssetTransfer.reward(address(this), to, rewardCoin(), amount);

        emit ClaimInviteRewards(msg.sender, amount, signature.s);
    }

    function getPhaseItemRewards(uint phase, Item item) public view returns(uint){
        uint _item = uint(item);
        require(_item <= (itemRatesLength() -1), "Illegal item");
        uint phaseReceivedJackpot = phaseReceivedJackpot(phase);
        return phaseReceivedJackpot.mul(itemRates(_item)).div(100);
    }

    function withdraw(address _asset, address _to, uint256 _amount) public onlyOwner{
        require(_to != address(0),"WithdrawAsset: _to the zero address");
        uint256 amount = _asset == address(0) ? address(this).balance : IERC20(_asset).balanceOf(address(this));
        require(_amount >0 && _amount <= amount);
        AssetTransfer.reward(address(this), _to, _asset, _amount);

        emit WithdrawAsset(msg.sender, _to, _asset, _amount);
    }

    receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }
}
