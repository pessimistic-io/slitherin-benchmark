// SPDX-License-Identifier: MIT

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./SushiLibs.sol";

contract VaultMiner is Context, Ownable, ReentrancyGuard {

    using SafeERC20 for IERC20;
    
    IERC20 private token;

    // where the tokens get sent too after buys, default to burn
    address private tokenReceiver = address(0xdead);

    IUniswapV2Router02 public immutable swapRouter;
    address private  swapPair;

    uint256 public constant COST_FOR_SHARE = 1080000;
    uint256 private PSN = 10000;
    uint256 private PSNH = 5000;
    

    bool private initialized = false;
    address payable private treasuryWallet;
    address payable private investWallet;
    address payable private devWallet;

    mapping (address => uint256) private userShares;
    mapping (address => uint256) private claimedWorkers;
    mapping (address => address) private referrals;
    mapping (address => uint256) private lastClaim;
    mapping (address => IERC20) public harvestToken;

    mapping(address => bool) private canGive;
    uint256 public marketWorkers;

    uint256 public totalShares;    

    // hard cap Penalty fee of 60% max
    uint256 private constant MAX_PENALTY_FEE = 600;

    // hard cap buy in fee of 20% max
    uint256 private constant MAX_BUY_FEE = 200;

    // hard cap of 15% on the referral fees
    uint256 private constant MAX_REF_FEE = 150;

    struct ActiveFeatures {
        bool minerActive;
        bool lpEnabled; // if we add to lp or not
        bool minerBuy; // buying/selling in the miner 
        bool minerCompound; // compounding 
    }

    struct FeesInfo {
        uint256 refFee;
        uint256 buyFee;
        uint256 devFee;
        uint256 treasuryFee;
        uint256 investFee;
        uint256 buyPenalty;
        uint256 devPenalty;
        uint256 treasuryPenalty;
        uint256 investPenalty;
    }

    struct UserStats {
        uint256 purchases; // how many times they bought shares
        uint256 purchaseAmount; // total amount they have purchased
        uint256 purchaseValue; // total value they have purchased 
        uint256 compounds; // how many times they have compounded
        uint256 compoundAmount; // total amount they have compounded
        uint256 compoundValue; // total value they have compounded (at time of compound) 
        uint256 lastSell; // timestamp of last sell
        uint256 sells; // how many times they sold shares
        uint256 sellAmount; // total amount they have sold
        uint256 sellValue; // total value they have sold
        uint256 firstBuy; //when they made their first buy
        uint256 refRewards; // total value of ref rewards (at time of purchase) 
        uint256 lastReset; // the time stamp if they reset the account and GTFO
    }

    

    struct MultiplierInfo {
        uint256 nftId; 
        uint256 lifetime; // time in seconds this is active 
        uint256 startTime; // time stamp it was staked
        uint256 endTime; // time stamp it when it ends
        uint256 multiplier;  // multiply new shares by this amount (only applies to type 1)
    }

    struct MinerSettings {
        uint256 maxPerAddress;
        uint256 minBuy;
        uint256 maxBuy;
        uint256 minRefAmount;
        uint256 maxRefMultiplier;
        uint256 sellDuration;
        // bool buyFromTokenEnabled;
        bool noSell;
        bool refCompoundEnabled;
        uint256 pendingLock;
    }
  
    
    mapping(address => MultiplierInfo) public currentMultiplier;
    mapping(address => UserStats) public userStats;
    ActiveFeatures public activeFeatures;
    FeesInfo public fees;
    MinerSettings public minerSettings;

    // event FeeChanged(uint256 refFee, uint256 fee, uint256 penaltyFees, uint256 timestamp);

    constructor(
        address payable _devWallet, 
        address payable _treasuryWallet, 
        address payable _investWallet, 
        IERC20 _token, 
        address _router) {

        treasuryWallet = payable(_treasuryWallet);
        investWallet = payable(_investWallet);
        devWallet = payable(_devWallet);

        token = _token;

        
        // 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
        IUniswapV2Router02 _swapRouter = IUniswapV2Router02(
            _router
        );
        // get a uniswap pair for this token
        swapPair = IUniswapV2Factory(_swapRouter.factory()).createPair(address(this), _swapRouter.WETH());
        
        swapRouter = _swapRouter;

        IERC20(swapPair).approve(address(_swapRouter), type(uint256).max);
        token.approve(address(this), type(uint256).max);
        

        // default fees
        fees = FeesInfo({
            refFee: 90,
            buyFee: 20,
            devFee: 6,
            treasuryFee: 34,
            investFee: 0,
            buyPenalty: 200,
            devPenalty: 60,
            treasuryPenalty: 340,
            investPenalty: 0
        });

        // default settings
        minerSettings = MinerSettings({
            maxPerAddress: 10000 * 1 ether,
            minBuy: 5 * 1 ether,
            maxBuy: 1000 * 1 ether,
            minRefAmount: 50 * 1 ether,
            maxRefMultiplier: 30,
            sellDuration: 6 days,
            // buyFromTokenEnabled: true,
            noSell: false,
            refCompoundEnabled: false,
            pendingLock: 3
        });
    }
    
    event SetHarvestToken(address indexed user, IERC20 token);
    function setHarvestToken(IERC20 _harvestToken)  external {
        harvestToken[msg.sender] = _harvestToken;
        emit SetHarvestToken(msg.sender, _harvestToken);
    }
    
    function claimWorkers(address ref) public _isInitialized nonReentrant {
        _claimWorkers(msg.sender,ref, false);
    }

    function vaultClaimWorkers(address addr, address ref) public _isInitialized {
        require(canGive[msg.sender], "Not Allowed");
        _claimWorkers(addr,ref, false);
    }

    function getMaxRefRewards(address addr) public view returns(uint256){
        return (userStats[addr].purchaseValue * minerSettings.maxRefMultiplier) / 10;
    }

    function getLastReset(address _addr) external view returns(uint256){
        return userStats[_addr].lastReset; 
    }
    
    event WorkersClaimed(address indexed user, address indexed ref, bool isBuy, uint256 newShares, uint256 userWorkers, uint256 refWorkers, uint256 refRewards, uint256 compoundValue, uint256 marketWorkers, uint256 timestamp);
    function _claimWorkers(address addr, address ref, bool isBuy) private {
        require(activeFeatures.minerActive && activeFeatures.minerCompound, 'disabled');
        // require(isBuy || block.timestamp > (lastClaim[addr] + compoundDuration), 'Too soon' );
        if(ref == addr) {
            ref = address(0);
        }
        
        if(referrals[addr] == address(0) && referrals[addr] != addr && referrals[referrals[addr]] != addr) {
            referrals[addr] = ref;
        }

        bool hasRef = referrals[addr] != address(0) && referrals[addr] != addr && userStats[referrals[addr]].purchaseValue >= minerSettings.minRefAmount;
        
        uint256 workersUsed = getMyWorkers(addr);
        // uint256 userWorkers;
        uint256 refWorkers;
        uint256 refRewards;
        if(hasRef && (isBuy || minerSettings.refCompoundEnabled)) {
            refWorkers = getFee(workersUsed,fees.refFee);
            refRewards = calculateWorkerSell(refWorkers);
            // check if we hit max ref rewards
            if((userStats[referrals[addr]].refRewards + refRewards) < getMaxRefRewards(referrals[addr]) ){
                
                //send referral workers
                claimedWorkers[referrals[addr]] = claimedWorkers[referrals[addr]] + refWorkers;
                userStats[referrals[addr]].refRewards = userStats[referrals[addr]].refRewards + refRewards;
            } else {
                refWorkers = 0;
                refRewards = 0;
            }
        }
       
        uint256 compoundValue = 0;

        if(isBuy){
            userStats[addr].purchases = userStats[addr].purchases + 1;
            userStats[addr].purchaseAmount = userStats[addr].purchaseAmount + workersUsed; 
        } else {
            compoundValue = calculateWorkerSell(workersUsed);
            userStats[addr].compounds = userStats[addr].compounds + 1;
            userStats[addr].compoundAmount = userStats[addr].compoundAmount + workersUsed; 
            userStats[addr].compoundValue = userStats[addr].compoundValue + compoundValue; 
        }

        // uint256 newShares = userWorkers/COST_FOR_SHARE;
        uint256 newShares = workersUsed/COST_FOR_SHARE;
        
        userShares[addr] = userShares[addr] + newShares;
        totalShares = totalShares + newShares;

        claimedWorkers[addr] = 0;
        lastClaim[addr] = block.timestamp;
         
        //boost market to nerf shares hoarding
        marketWorkers = marketWorkers + (workersUsed/5);

        emit WorkersClaimed(addr, referrals[addr], isBuy, newShares, workersUsed, refWorkers, refRewards, compoundValue, marketWorkers, block.timestamp);
    }


    event WorkersSold(address indexed user,  uint256 amount, uint256 workersSold, uint256 marketWorkers, uint256 toUser, uint256 toFees, uint256 timestamp );
    function sellWorkers() public _isInitialized nonReentrant {
        require(activeFeatures.minerActive && activeFeatures.minerBuy && (!minerSettings.noSell || block.timestamp > (userStats[msg.sender].lastSell + minerSettings.sellDuration)), 'too soon to sell');

        uint256 hasWorkers = getMyWorkers(msg.sender);
        uint256 workerValue = calculateWorkerSell(hasWorkers);

        uint256 fee = getFee(workerValue,totalFees());
        uint256 toBuy = getFee(workerValue,fees.buyFee);
        uint256 toDev = getFee(workerValue,fees.devFee);
        uint256 toTreasury = getFee(workerValue,fees.treasuryFee);
        uint256 toInvest = getFee(workerValue,fees.investFee);

        uint256 sellTime = userStats[msg.sender].lastSell + minerSettings.sellDuration;

        if(!minerSettings.noSell && block.timestamp < sellTime){
            // use the penalty fees
            // scale down from penalty fee to 2x the normal fee over time
            uint256 timeDelta = block.timestamp - userStats[msg.sender].lastSell;
            uint256 penaltyMod = (timeDelta * 10000)/minerSettings.sellDuration;
            uint256 feeCheck = (totalPenalty() * penaltyMod)/10000;
            uint256 minFee = totalFees() * 2;
            

            if( feeCheck > minFee){
                fee = (getFee(workerValue, (totalPenalty())) * penaltyMod)/10000;
                toBuy = (getFee(workerValue,fees.buyPenalty) * penaltyMod)/10000;
                toDev = (getFee(workerValue,fees.devPenalty) * penaltyMod)/10000;
                toTreasury = (getFee(workerValue,fees.treasuryPenalty) * penaltyMod)/10000;
                toInvest = (getFee(workerValue,fees.investPenalty) * penaltyMod)/10000;
            } else {
                fee = getFee(workerValue,totalFees() * 2);
                toBuy = getFee(workerValue,fees.buyFee * 2);
                toDev = getFee(workerValue,fees.devFee * 2);
                toTreasury = getFee(workerValue,fees.treasuryFee * 2);
                toInvest = getFee(workerValue,fees.investFee * 2);
            }
        }

        claimedWorkers[msg.sender] = 0;
        lastClaim[msg.sender] = block.timestamp;
        marketWorkers = marketWorkers + hasWorkers;

        userStats[msg.sender].lastSell = block.timestamp; 
        userStats[msg.sender].sells = userStats[msg.sender].sells + 1; 
        userStats[msg.sender].sellAmount = userStats[msg.sender].sellAmount + hasWorkers;
        userStats[msg.sender].sellValue = userStats[msg.sender].sellValue + (workerValue-fee);

        bool sent;
        if(toDev > 0) {
            (sent,) = devWallet.call{value: (toDev)}("");
            require(sent,"send failed");
        }

        if(toTreasury > 0) {
            (sent,) = treasuryWallet.call{value: (toTreasury)}("");
            require(sent,"send failed");
        }

        if(toInvest > 0) {
            (sent,) = investWallet.call{value: (toInvest)}("");
            require(sent,"send failed");
        }

        if(toBuy > 0) {
            swapFromFees(toBuy);
        }

        uint256 toSend = workerValue - toDev - toTreasury - toInvest - toBuy;
        if(harvestToken[msg.sender] == IERC20(address(0))){
            // send to the user
            (sent,) = payable(msg.sender).call{value: toSend}("");
            require(sent,"send failed");
        } else {
            _swapNativeForToken(toSend, harvestToken[msg.sender], msg.sender); 
        }

        emit WorkersSold(msg.sender, workerValue, hasWorkers, marketWorkers, toSend, (workerValue - toSend), block.timestamp);
    }
    
    function pendingRewards(address adr) public view returns(uint256) {
        uint256 hasWorkers = getMyWorkers(adr);
        if(hasWorkers == 0){
            return 0;
        }
        uint256 workerValue = calculateWorkerSell(hasWorkers);
        return workerValue;
    }
    
    function buyWorkers(address ref) public payable _isInitialized nonReentrant {
        return _buyWorkers(msg.sender, msg.value, ref, false);
    }

    function contractBuyWorkers(address _user, address _ref) public payable _isInitialized nonReentrant {
        require(canGive[msg.sender], "Not Allowed");
        return _buyWorkers(_user, msg.value, _ref, true);
    }

    function setCurrentMultiplier(
        address _user, 
        uint256 _nftId, 
        uint256 _lifetime, 
        uint256 _startTime, 
        uint256 _endTime, 
        uint256 _multiplier
    ) public {
        require(canGive[msg.sender], "Not Allowed");

        currentMultiplier[_user].nftId = _nftId;
        currentMultiplier[_user].lifetime = _lifetime;
        currentMultiplier[_user].startTime = _startTime;
        currentMultiplier[_user].endTime = _endTime;
        currentMultiplier[_user].multiplier = _multiplier;

    }

    event WorkersBought(address indexed user, address indexed ref, uint256 amount, uint256 workersBought, bool fromSwap, uint256 timestamp );
    function _buyWorkers(address user, uint256 amount, address ref,  bool fromSwap) private {
        // require(amount >= minerSettings.minBuy, 'Buy too small');
        require(activeFeatures.minerActive && activeFeatures.minerBuy && amount >= minerSettings.minBuy && amount <= minerSettings.maxBuy, 'Cant Buy');
        require(minerSettings.maxPerAddress == 0 || (userStats[user].purchaseValue + amount) <= minerSettings.maxPerAddress, 'Max buy amount reached');

        uint256 fee = totalFees();
        
        uint256 workersBought = calculateWorkerBuy(amount,(address(this).balance - amount));
        workersBought = workersBought - getFee(workersBought,fee);

        // see if we have a valid multiplier nft
        if(currentMultiplier[user].startTime > 0) {
            if(currentMultiplier[user].endTime < block.timestamp) {
                // expired, reset the current multiplier
                delete currentMultiplier[user];
            } else {
                // valid multiplier, multiply the post fee amount 
                workersBought = ((workersBought * currentMultiplier[user].multiplier)/100);
            }
        }

        uint256 toBuy = getFee(amount,fees.buyFee);
        uint256 toDev = getFee(amount,fees.devFee);
        uint256 toTreasury = getFee(amount,fees.treasuryFee);
        uint256 toInvest = getFee(amount,fees.investFee);

        if(userStats[user].firstBuy == 0){
            userStats[user].firstBuy = block.timestamp;
        }

        userStats[user].purchaseValue = userStats[user].purchaseValue + amount; 
        
        bool sent;
        // send the fee to the treasuryWallet
        if(toDev > 0) {
            (sent,) = devWallet.call{value: (toDev)}("");
            require(sent,"send failed");
        }

        if(toTreasury > 0) {
            (sent,) = treasuryWallet.call{value: (toTreasury)}("");
            require(sent,"send failed");
        }

        // send to the invest wallet
        if(toInvest > 0) {
            (sent,) = investWallet.call{value: (toInvest)}("");
            require(sent,"send failed");
        }

        // do the buyback
        if(toBuy > 0) {
            swapFromFees(toBuy);
        }

        claimedWorkers[user] = claimedWorkers[user] + workersBought;

        emit WorkersBought(user, ref, amount, workersBought, fromSwap, block.timestamp );

        _claimWorkers(msg.sender,ref,true);
    }

    


    function calculateTrade(uint256 rt,uint256 rs, uint256 bs) private view returns(uint256) {
        return (PSN * bs)/(PSNH + ( ((PSN * rs) + (PSNH * rt))/rt) );
    }
    
    function calculateWorkerSell(uint256 workers) public view returns(uint256) {
        return calculateTrade(workers,marketWorkers,address(this).balance);
    }
    
    function calculateWorkerBuy(uint256 amount,uint256 contractBalance) public view returns(uint256) {
        return calculateTrade(amount,contractBalance,marketWorkers);
    }
    
    function calculateWorkerBuySimple(uint256 amount) public view returns(uint256) {
        return calculateWorkerBuy(amount,address(this).balance);
    }
    
    function totalFees() private view returns(uint256) {
        return fees.buyFee + fees.devFee + fees.treasuryFee + fees.investFee;
    }

    function totalPenalty() private view returns(uint256) {
        return fees.buyPenalty + fees.devPenalty + fees.treasuryPenalty + fees.investPenalty;
    }

    function getFee(uint256 amount, uint256 fee) private pure returns(uint256) {
        return (amount * fee)/1000;
    }
    
    event MarketInitialized(uint256 startTime, uint256 marketWorkers);
    function seedMarket() public payable onlyOwner {
        require(marketWorkers == 0);

        initialized = true;
        marketWorkers = 108000000000;

        emit MarketInitialized(block.timestamp, marketWorkers);
    }


    function setContracts(IERC20 _token) public onlyOwner {
        token = _token;
    }
    
    // manage which contracts/addresses can give shares to allow other contracts to interact
    function setCanGive(address _addr, bool _canGive) public onlyOwner {
        canGive[_addr] = _canGive;
    }


    function setWallets(
        address _devWallet, 
        address _treasuryWallet, 
        address _investWallet, 
        address _tokenReceiver 
    ) public onlyOwner {
        devWallet = payable(_devWallet);
        treasuryWallet = payable(_treasuryWallet);
        investWallet = payable(_investWallet);
        tokenReceiver = _tokenReceiver;
    }

    event FeeChanged(
        uint256 refFee, 
        uint256 buyFee, 
        uint256 devFee,
        uint256 treasuryFee, 
        uint256 investFee, 
        uint256 buyPenalty, 
        uint256 devPenalty, 
        uint256 treasuryPenalty,
        uint256 investPenalty
    );

    function setFees(
        uint256 _refFee,
        uint256 _buyFee, 
        uint256 _devFee, 
        uint256 _treasuryFee,
        uint256 _investFee,
        uint256 _buyPenalty, 
        uint256 _devPenalty, 
        uint256 _treasuryPenalty,
        uint256 _investPenalty
    ) public onlyOwner {

        require(_refFee <= MAX_REF_FEE && (_buyFee + _devFee + _treasuryFee + _investFee) <= MAX_BUY_FEE && (_buyPenalty + _devPenalty + _treasuryPenalty + _investPenalty) <= MAX_PENALTY_FEE, 'fee too high');
        // require((_buyFee + _devFee + _investFee) <= MAX_BUY_FEE, "Fee capped at 20%");
        // require((_buyPenalty + _devPenalty + _investPenalty) <= MAX_PENALTY_FEE, "Penalty capped at 60%");

         fees = FeesInfo({
            refFee: _refFee,
            buyFee: _buyFee,
            devFee: _devFee,
            treasuryFee: _treasuryFee,
            investFee: _investFee,
            buyPenalty: _buyPenalty,
            devPenalty: _devPenalty,
            treasuryPenalty: _treasuryPenalty,
            investPenalty: _investPenalty
        });

         
         emit FeeChanged(
            _refFee,
            _buyFee,
            _devFee,
            _treasuryFee,
            _investFee,
            _buyPenalty,
            _devPenalty,
            _treasuryPenalty,
            _investPenalty
        );
        // emit FeeChanged(_refFee, (_buyFee + _devFee + _treasuryFee + _investFee), (_buyPenalty + _devPenalty + _treasuryPenalty + _investPenalty), block.timestamp);
    }

    event ActiveFeaturesSet(bool minerActive, bool lpEnabled, bool minerBuy, bool minerCompound);
    function setActiveFeatures(
        bool _minerActive,
        bool _lpEnabled, // if we add to lp or not
        bool _minerBuy, 
        bool _minerCompound
    ) public onlyOwner {
        activeFeatures.minerActive = _minerActive;
        activeFeatures.lpEnabled = _lpEnabled;
        activeFeatures.minerBuy = _minerBuy;
        activeFeatures.minerCompound = _minerCompound;
        emit ActiveFeaturesSet(_minerActive, _lpEnabled, _minerBuy, _minerCompound);
    }

    event MinerSettingsSet(
        uint256 maxPerAddress, 
        uint256 minBuy, 
        uint256 maxBuy,
        uint256 minRefAmount, 
        uint256 maxRefMultiplier,
        uint256 sellDuration,
        // bool _buyFromTokenEnabled,
        bool noSell,
        bool refCompoundEnabled,
        uint256 pendingLock);

    function setMinerSettings(
        uint256 _maxPerAddress, 
        uint256 _minBuy, 
        uint256 _maxBuy,
        uint256 _minRefAmount, 
        uint256 _maxRefMultiplier,
        uint256 _sellDuration,
        // bool _buyFromTokenEnabled,
        bool _noSell,
        bool _refCompoundEnabled,
        uint256 _pendingLock
    ) public onlyOwner {
        

         minerSettings = MinerSettings({
            maxPerAddress: _maxPerAddress,
            minBuy: _minBuy,
            maxBuy: _maxBuy,
            minRefAmount: _minRefAmount,
            maxRefMultiplier: _maxRefMultiplier,
            sellDuration: _sellDuration,
            // buyFromTokenEnabled: _buyFromTokenEnabled,
            noSell: _noSell,
            refCompoundEnabled: _refCompoundEnabled,
            pendingLock: _pendingLock
        });

         emit MinerSettingsSet(
            _maxPerAddress,
            _minBuy,
            _maxBuy,
            _minRefAmount,
            _maxRefMultiplier,
            _sellDuration,
            _noSell,
            _refCompoundEnabled,
            _pendingLock
        );
    }
    
    function getBalance() public view returns(uint256) {
        return address(this).balance;
    }
    
    function getTotalShares() external view returns(uint256) {
        return totalShares;
    }

    function getMyShares(address adr) public view returns(uint256) {
        return userShares[adr];
    }
    
    function getMyWorkers(address adr) public view returns(uint256) {
        return claimedWorkers[adr] + getWorkersSinceLastClaim(adr);
    }
    
    function getWorkersSinceLastClaim(address adr) public view returns(uint256) {
        uint256 secondsPassed;

        // if last claim is > 24 hours lock it
        if(minerSettings.pendingLock > 0 && (lastClaim[adr] + (minerSettings.pendingLock * 1 days)) < block.timestamp ){
            secondsPassed = (minerSettings.pendingLock * 1 days);
        } else {
            secondsPassed=min(COST_FOR_SHARE,(block.timestamp - lastClaim[adr]));
        }
        return secondsPassed * userShares[adr];
    }

    function getReferral(address adr) public view returns(address) {
        return referrals[adr];
    }

    function getLastClaim(address adr) public view returns(uint256) {
        return lastClaim[adr];
    }

    function getSharesValue(uint256 shares) public view returns(uint256) {
        return calculateWorkerSell(shares * COST_FOR_SHARE);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function isInitialized() external view returns (bool){
        return initialized;
    }

    function giveShares(address _addr, uint256 _amount, bool _forceClaim) public {
        require(canGive[msg.sender], "Can't give");
        _addShares(_addr,_amount,_forceClaim);
    }

    function removeShares(address _addr, uint256 _amount) public {
        require(canGive[msg.sender], "Can't remove");
        _removeShares(_addr,_amount,false);
    }

    //adds shares
    function _addShares(address _addr, uint256 _amount, bool _forceClaim) private {

        claimedWorkers[_addr] = claimedWorkers[_addr] + (_amount * COST_FOR_SHARE) / 1 ether;
        if(_forceClaim){
            _claimWorkers(_addr,_addr,false);
        }
    }

    event SharesRemoved(address indexed user, uint256 amount, uint256 marketWorkers);
    //removes shares
    function _removeShares(address _addr, uint256 _amount, bool direct) private {
        // claim first
        if(!direct){
            _claimWorkers(_addr,_addr,false);
        }

        uint256 toRemove = _amount/ 1 ether;
        userShares[_addr] = userShares[_addr] - toRemove;
        totalShares = totalShares - toRemove;
        
        // remove workers from the market

        marketWorkers = marketWorkers - ((toRemove * COST_FOR_SHARE)/5);
        emit SharesRemoved(_addr, toRemove, marketWorkers);
    }

    /**
     * @dev Exit the vault by giving up all of your shares
     * We give up to 50% of the shares value, up to their initial investment
     * user data is reset 
     */
    event UserGTFO(address indexed user, uint256 shares, uint256 amount, uint256 timestamp); 
    function GTFO() public nonReentrant {
        require(userStats[msg.sender].purchaseValue > 0, 'No Bought Shares');
        require(block.timestamp >= (userStats[msg.sender].lastSell + minerSettings.sellDuration), 'too soon');
        _claimWorkers(msg.sender,msg.sender,false);

        uint256 shares = getMyShares(msg.sender);
        uint256 maxReturn = getSharesValue(shares)/2;
        uint256 toSend = maxReturn;

        if(maxReturn > userStats[msg.sender].purchaseValue){
            toSend = userStats[msg.sender].purchaseValue;
        }


        // reset the user
        delete userStats[msg.sender];

        // flag the reset
        userStats[msg.sender].lastReset = block.timestamp;

        // remove the shares
        _removeShares(msg.sender,shares * 1 ether,true);

        if(toSend > 0) {
            (bool sent,) = payable(msg.sender).call{value: (toSend)}("");
            require(sent,"send failed");
        }

        emit UserGTFO(msg.sender, shares, toSend, block.timestamp);

    }
/*
    function buyFromToken(uint256 tokenAmount, IERC20 tokenAddress, address ref) public isInitialized {
        require(minerSettings.buyFromTokenEnabled,'not enabled');

        // transfer the ERC20 token
        tokenAddress.safeTransferFrom(address(msg.sender), address(this), tokenAmount);

        // get current balance
        uint256 currentBalance = address(this).balance;

        // do the swap
        swapTokenForNative(tokenAmount, tokenAddress);

        // get new balance and amount to buy
        uint256 toBuy = address(this).balance - currentBalance;

        // make the buy
        _buyWorkers(msg.sender,toBuy,ref,true);
    }


    function swapTokenForNative(uint256 tokenAmount, IERC20 tokenAddress) private {
        _swapTokenForNative(tokenAmount, tokenAddress, address(this));
    }


    //swaps tokens on the contract for Native
    function _swapTokenForNative(uint256 tokenAmount, IERC20 fromToken, address toAddress) private {
        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = swapRouter.WETH();

        swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(toAddress),
            block.timestamp
        );
    }

*/    
    function swapFromFees(uint256 amount) private {
         _swapNativeForToken(amount, token, address(tokenReceiver));
    }

    //swaps Native for a token
    function _swapNativeForToken(uint256 amount, IERC20 toToken, address toAddress) private {
        address[] memory path = new address[](2);
        path[0] = swapRouter.WETH();
        path[1] = address(toToken);

        swapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            address(toAddress),
            block.timestamp
        );
    }

    // LP Functions
    //Adds Liquidity directly to the contract where LP are locked
    function _addLiquidity(uint256 tokenamount, uint256 nativeamount) private {
        // vaultStats.totalLPNative+=nativeamount;
        // vaultStats.totalLPToken+=tokenamount;
        token.approve(address(swapRouter), tokenamount);
        try swapRouter.addLiquidityETH{value: nativeamount}(
            address(token),
            tokenamount,
            0,
            0,
            address(this),
            block.timestamp
        ){}
        catch{}
    }

    function extendLiquidityLock(uint256 secondsUntilUnlock) public onlyOwner {
        uint256 newUnlockTime = secondsUntilUnlock+block.timestamp;
        require(newUnlockTime>liquidityUnlockTime);
        liquidityUnlockTime=newUnlockTime;
    }

    // unlock time for contract LP
    uint256 public liquidityUnlockTime;

    // default for new lp added after release
    uint256 private constant DefaultLiquidityLockTime=3 days;

    //Release Liquidity Tokens once unlock time is over
    function releaseLiquidity() public onlyOwner {
        //Only callable if liquidity Unlock time is over
        require(block.timestamp >= liquidityUnlockTime, "Locked");
        liquidityUnlockTime=block.timestamp+DefaultLiquidityLockTime;       
        IERC20Uniswap liquidityToken = IERC20Uniswap(swapPair);
        // uint256 amount = liquidityToken.balanceOf(address(this));

        // only allow 20% 
        // amount=amount*2/10;
        liquidityToken.transfer(treasuryWallet, (liquidityToken.balanceOf(address(this)) * 2) / 10);
    }

    event OnVaultReceive(address indexed sender, uint256 amount, uint256 toHolders, uint256 toLp);
    receive() external payable {

        // @TODO
        // Check if it's coming from the gateway address
        // don't add LP (LP added to sidechains pool)

        // Send half to LP
        uint256 lpBal = msg.value / 2;
        uint256 shareBal = msg.value - lpBal;

        //if we have no shares 100% LP    
        if(totalShares <= 0){
            lpBal = msg.value;
            shareBal = 0;
        }

        // return change to all the share holders 
        if(!activeFeatures.lpEnabled || msg.sender == address(swapRouter)){
            lpBal = 0;
            shareBal = msg.value;
        } else {

            // split the LP part in half
            uint256 nativeToSpend = lpBal / 2;
            uint256 nativeToPost = lpBal - nativeToSpend;

            // get the current mPCKT balance
            uint256 contractTokenBal = token.balanceOf(address(this));
           
            // do the swap
            _swapNativeForToken(nativeToSpend,token, address(this));

            //new balance
            uint256 tokenToPost = token.balanceOf(address(this)) - contractTokenBal;

            // add LP
            _addLiquidity(tokenToPost, nativeToPost);
        }

        emit OnVaultReceive(msg.sender, msg.value, shareBal, lpBal);
    }

    // move any tokens sent to the contract
    function teamTransferToken(address tokenAddress, address recipient, uint256 amount) external onlyOwner {
        require(tokenAddress != address(0), "Invalid Address");
        IERC20 _token = IERC20(tokenAddress);
        _token.safeTransfer(recipient, amount);
    }


    // pull all the native out of the contract, needed for migrations/emergencies
    function withdrawETH() external onlyOwner {
         (bool sent,) =address(owner()).call{value: (address(this).balance)}("");
        require(sent,"withdraw failed");
    }

    modifier _isInitialized {
      require(initialized, "Vault Miner has not been initialized");
      _;
    }
}
