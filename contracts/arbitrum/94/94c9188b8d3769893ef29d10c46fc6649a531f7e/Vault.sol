// SPDX-License-Identifier: MIT
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./IERC1155Receiver.sol";
import "./ERC1155Tradable.sol";
import "./SushiLibs.sol";
import "./IVault.sol";

contract Vault  is Context, Ownable, IERC1155Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct ActiveFeatures {
        bool vaultActive; // global active flag
        bool giveNfts; // locking, giving and burning nfts
        bool burnTokens; // buring tokeins for hares
        bool useNft; // using vault NFTS
    }

    struct VaultStats {
        // uint256 totalLPNative; // total Native added to LP
        // uint256 totalLPToken; // total token added to LP
        uint256 totalTokensBurned; // total tokens burne
    }

    struct VaultContracts {
        ERC1155Tradable nftContract; // Nft contract
        address nftPacks; // Nft Packs Address
        address nftRewards; // Nft Rewards Address
        IVaultMiner minerContract; // miner contract
        address lpAddress; //LP token are locked in the contract
    }

    struct VaultSettings {
        uint256 tokenBurnMultiplier;
        uint256 nftGiveMultiplier;
        uint256 nftBurnMultiplier;
        uint256 packThresh;
        uint256 burnThresh;
        uint256 shareMod;
        uint256 tokenShare;
        uint256 tokenPercent;
    }
   
    struct UserLock {
        uint256 tokenAmount; // total amount they locked
        uint256 claimedAmount; // total amount they have withdrawn
        uint256 vestShare; // how many tokens they get back each vesting period
        uint256 vestPeriod; // how many seconds each vest point is
        uint256 startTime; // start of the lock
        uint256 endTime; //when the lock ends
    }

    struct UserNftLock {
        uint256 amount; // amount they have locked
        uint256 sharePoints;  // total share points being given for this lock
        uint256 startTime; // start of the lock
        uint256 endTime; //when the lock ends
    }

    struct NftInfo {
        uint256 tokenId; // which token to lock (mPCKT or LP)
        uint256 lockDuration; // how long this nft needs you to lock
        uint256 tokenAmount; // how many tokens you must lock
        uint256 vestPoints; // lock time / vestPoints = each vesting period
        uint256 sharePoints;  // how many base share this is worth for locking (4x for giving)
        uint256 sharePercent;  // % value of vault shares, applies when value is > sharePoints
        uint256 givenAmount; // how many have been deposited into the contract
        uint256 burnedAmount; // how many have been deposited into the contract
        uint256 claimedAmount; // how many have been claimed from the contract
        uint256 lockedNfts; // how many nfts are currently locked
        bool toBurn; // if this should be burned or transferred when deposited
        bool isDisabled; // so we can hide ones we don't want
        address lastGiven; // address that last gave this nft so they can't reclaim
    } 

    struct VaultNftInfo {
        uint256 nftType; // 1 for percent - 2 for instant shares 1:1 - 3 for instant shares adjusted
        uint256 amount; // how many shares this gives (only applies to type 2)
        uint256 lifetime; // time in seconds this is active (only applies to type 1)
        uint256 multiplier;  // multiply new shares by this amount (only applies to type 1)
        uint256 totalUsed; // how many nfts were used
        bool isDisabled; // so we can hide ones we don't want
    }

    VaultSettings public vaultSettings;
    VaultContracts public vaultContracts;
    VaultStats public vaultStats;
    mapping(address => mapping(uint256 => UserLock)) public userLocks;
    mapping(address => mapping(uint256 => UserNftLock)) public userNftLocks;
    mapping(uint256 => NftInfo) public nftInfo;
    mapping(uint256 => VaultNftInfo) public vaultNftInfo;
    mapping(uint256 => bool) public inNftPacks;
    mapping(uint256 => bool) public inNftRewards;
    mapping(uint256 => IERC20) public tokenIds;
    mapping(address => bool) private canGive;

    ActiveFeatures public activeFeatures;

    // hard cap on the max NFT multiplier 3x max
    uint256 private constant MAX_NFT_MULTIPLIER = 300;

     // The burn address
    address public constant burnAddress = address(0xdead);
    address payable internal treasuryWallet;

    IUniswapV2Router02 public immutable swapRouter;
    address internal  swapPair;

    
    event Locked(address indexed user, uint256 nftId, uint256 amount, uint256 vestShare, uint256 vestPeriod, uint256 startTime, uint256 endTime );
    event UnLocked(address indexed user, uint256 nftId);
    event Claimed(address indexed user, uint256 nftId, uint256 amount);
    event NftGiven(address indexed user, uint256 nftId, uint256 amount, uint256 shares, bool toBurn);
    event NftLocked(address indexed user, uint256 nftId, uint256 amount, uint256 shares, uint256 startTime, uint256 endTime);
    event TokensBurned(address indexed user, uint256 amount, uint256 shares);
    event NftUnLocked(address indexed user, uint256 nftId, uint256 amount);
    event MultipliersSet(uint256 tokenBurn, uint256 nftGive, uint256 nftBurn);
    event ThresholdsSet(uint256 packThresh, uint256 burnThresh, uint256 shareMod,  uint256 tokenShare,  uint256 tokenPercent);

    constructor (
        IVaultMiner _minerContract,
        ERC1155Tradable _nftContract, 
        IERC20 _token, 
        address payable _treasuryWallet,
        address _lpAddress, 
        address _router
    ) {

        treasuryWallet = _treasuryWallet;
        vaultContracts.nftContract = _nftContract;
        vaultContracts.minerContract = _minerContract;

        canGive[address(this)] = true;

        vaultContracts.lpAddress  = _lpAddress;
            
        // default settings
        vaultSettings = VaultSettings({
            tokenBurnMultiplier: 6,
            nftGiveMultiplier: 4,
            nftBurnMultiplier: 3,
            packThresh: 3,
            burnThresh: 100,
            shareMod: 300,
            tokenShare: 30,
            tokenPercent: 10
        });

        // emit default settings for the indexer
        emit MultipliersSet(vaultSettings.tokenBurnMultiplier,vaultSettings.nftGiveMultiplier,vaultSettings.nftBurnMultiplier);
        emit ThresholdsSet(vaultSettings.packThresh,vaultSettings.burnThresh,vaultSettings.shareMod,vaultSettings.tokenShare,vaultSettings.tokenPercent);
         

        // 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
        IUniswapV2Router02 _swapRouter = IUniswapV2Router02(
            _router
        );

        swapRouter = _swapRouter;

        _setToken(1,_token);
    }

    
    function setMultipliers(uint256 _tokenBurnMultiplier, uint256 _nftGiveMultiplier, uint256 _nftBurnMultiplier ) public onlyOwner {
        vaultSettings.tokenBurnMultiplier = _tokenBurnMultiplier;
        vaultSettings.nftGiveMultiplier = _nftGiveMultiplier;
        vaultSettings.nftBurnMultiplier = _nftBurnMultiplier;
        emit MultipliersSet(_tokenBurnMultiplier,_nftGiveMultiplier,_nftBurnMultiplier);
    }

    
    function setThresholds(
        uint256 _packThresh, 
        uint256 _burnThresh, 
        uint256 _shareMod, 
        uint256 _tokenShare, 
        uint256 _tokenPercent
    ) public onlyOwner {
        vaultSettings.packThresh = _packThresh;
        vaultSettings.burnThresh = _burnThresh;
        vaultSettings.shareMod = _shareMod;
        vaultSettings.tokenShare = _tokenShare;
        vaultSettings.tokenPercent = _tokenPercent;
        emit ThresholdsSet(_packThresh,_burnThresh,_shareMod,_tokenShare,_tokenPercent);
    }

    function setAddresses(
        address _lpAddress,
        ERC1155Tradable _nftContract,
        address _nftPacks,
        address _nftRewards,
        IVaultMiner _minerContract,
        address payable _treasuryWallet
    ) public onlyOwner {
        vaultContracts.lpAddress = _lpAddress;
        vaultContracts.nftContract = _nftContract;
        vaultContracts.nftPacks = _nftPacks;
        vaultContracts.nftRewards = _nftRewards;
        vaultContracts.minerContract = _minerContract;
        treasuryWallet = _treasuryWallet;
    }
  
    // manage which contracts/addresses can give shares to allow other contracts to interact
    function setCanGive(address _addr, bool _canGive) public onlyOwner {
        canGive[_addr] = _canGive;
    }

    function setToken(uint256 _tokenId, IERC20 _tokenAddress) public onlyOwner {
        _setToken(_tokenId, _tokenAddress);
    }

    function _setToken(uint256 _tokenId, IERC20 _tokenAddress) private {
        tokenIds[_tokenId] = _tokenAddress;
        _tokenAddress.approve(address(swapRouter), type(uint256).max);
        _tokenAddress.approve(address(this), type(uint256).max);
        
    }

    event SetInPacks(uint256 nftId, bool inPacks);
    function setNftInPack(uint256 _nftId, bool _inPacks) public onlyOwner {
        inNftPacks[_nftId] = _inPacks;
        emit SetInPacks(_nftId, _inPacks);
    }

    event SetInRewards(uint256 nftId, bool inRewards);
    function setNftInRewards(uint256 _nftId, bool _inRewards) public onlyOwner {
        inNftRewards[_nftId] = _inRewards;
        emit SetInRewards(_nftId, _inRewards);
    }

    event ActiveFeaturesSet(bool vaultActive, bool giveNfts, bool burnTokens, bool useNft);
    function setActiveFeatures(
        bool _vaultActive,
        bool _giveNfts, 
        bool _burnTokens, 
        bool _useNft
    ) public onlyOwner {
        activeFeatures.vaultActive = _vaultActive;
        activeFeatures.giveNfts = _giveNfts;
        activeFeatures.burnTokens = _burnTokens;
        activeFeatures.useNft = _useNft;

        emit ActiveFeaturesSet(_vaultActive,_giveNfts,_burnTokens,_useNft);
    }

    event NftInfoSet(
        uint256 nftId, 
        uint256 tokenId, 
        uint256 lockDuration, 
        uint256 tokenAmount, 
        uint256 vestPoints, 
        uint256 sharePoints, 
        uint256 sharePercent, 
        bool toBurn,
        bool inPacks,
        bool inRewards);

    function setNftInfo(
        uint256 _nftId, 
        uint256 _tokenId, 
        uint256 _lockDuration, 
        uint256 _tokenAmount, 
        uint256 _vestPoints, 
        uint256 _sharePoints, 
        uint256 _sharePercent, 
        bool _toBurn,
        bool _inPacks,
        bool _inRewards) public onlyOwner {

        

        require(address(tokenIds[_tokenId]) != address(0), "No valid token");

        inNftPacks[_nftId] = _inPacks;
        inNftRewards[_nftId] = _inRewards;

        nftInfo[_nftId].tokenId = _tokenId;
        nftInfo[_nftId].lockDuration = _lockDuration;
        nftInfo[_nftId].tokenAmount = _tokenAmount;
        nftInfo[_nftId].vestPoints = _vestPoints;
        nftInfo[_nftId].sharePoints = _sharePoints;
        nftInfo[_nftId].sharePercent = _sharePercent;
        nftInfo[_nftId].toBurn = _toBurn;

        emit NftInfoSet(
            _nftId, 
            _tokenId, 
            _lockDuration, 
            _tokenAmount, 
            _vestPoints, 
            _sharePoints, 
            _sharePercent, 
            _toBurn,
            _inPacks,
            _inRewards);

    }

    event SetNftDisabled(uint256 nftId, bool isDisabled);
    function setNftDisabled(uint256 _nftId, bool _isDisabled) public onlyOwner {
        nftInfo[_nftId].isDisabled = _isDisabled;        
        emit SetNftDisabled(_nftId, _isDisabled);
    }

    event SetVaultNft(uint256 nftId, uint256 nftType, uint256 amount, uint256 lifetime, uint256 multiplier);
    function setVaultNftInfo(
        uint256 _nftId, 
        uint256 _nftType,
        uint256 _amount,
        uint256 _lifetime,
        uint256 _multiplier) public onlyOwner {
        

        require(_multiplier <= MAX_NFT_MULTIPLIER, 'Multiplier too high');

        vaultNftInfo[_nftId].nftType = _nftType;
        vaultNftInfo[_nftId].amount = _amount; 
        vaultNftInfo[_nftId].lifetime = _lifetime; 
        vaultNftInfo[_nftId].multiplier = _multiplier; 

        emit SetVaultNft(_nftId, _nftType, _amount, _lifetime, _multiplier);

    }

    event SetVaultNftDisabled(uint256 nftId, bool isDisabled);
    function setVaultNftDisabled(uint256 _nftId, bool _isDisabled) public onlyOwner {
        vaultNftInfo[_nftId].isDisabled = _isDisabled;        
        emit SetVaultNftDisabled(_nftId, _isDisabled);
    }
/*
    function setVaultActive(bool _isActive) public onlyOwner {
        isActive = _isActive;
    }

    function setLpEnabled(bool _lpEnabled) public onlyOwner {
        lpEnabled = _lpEnabled;
    }*/

    function lock(uint256 _nftId) public nonReentrant {

        require(
            userLocks[msg.sender][_nftId].tokenAmount == 0 && 
            nftInfo[_nftId].lastGiven != address(msg.sender) &&    

            activeFeatures.vaultActive && activeFeatures.giveNfts && 
            tokenIds[nftInfo[_nftId].tokenId].balanceOf(msg.sender) >= nftInfo[_nftId].tokenAmount && 
            nftInfo[_nftId].tokenId  > 0 && !nftInfo[_nftId].isDisabled && 
            (vaultContracts.nftContract.balanceOf(address(this), _nftId) - nftInfo[_nftId].lockedNfts) > 0, 'Cant Lock');
        
        // require(activeFeatures.vaultActive && activeFeatures.giveNfts && tokenIds[nftInfo[_nftId].tokenId].balanceOf(msg.sender) >= nftInfo[_nftId].tokenAmount && nftInfo[_nftId].tokenId  > 0 && !nftInfo[_nftId].isDisabled && (nftContract.balanceOf(address(this), _nftId) - nftInfo[_nftId].lockedNfts) > 0, 'Not Enough');
        // require(nftInfo[_nftId].lastGiven != address(msg.sender),'can not claim your own' );

        userLocks[msg.sender][_nftId].tokenAmount = nftInfo[_nftId].tokenAmount;
        userLocks[msg.sender][_nftId].startTime = block.timestamp; // block.timestamp;
        userLocks[msg.sender][_nftId].endTime = block.timestamp + nftInfo[_nftId].lockDuration; // block.timestamp.add(nftInfo[_nftId].lockDuration);
        userLocks[msg.sender][_nftId].vestShare = nftInfo[_nftId].tokenAmount / nftInfo[_nftId].vestPoints;
        userLocks[msg.sender][_nftId].vestPeriod = nftInfo[_nftId].lockDuration / nftInfo[_nftId].vestPoints;


        // move the tokens
        tokenIds[nftInfo[_nftId].tokenId].safeTransferFrom(address(msg.sender), address(this), nftInfo[_nftId].tokenAmount);

        // send the NFT
        vaultContracts.nftContract.safeTransferFrom( address(this), msg.sender, _nftId, 1, "");

        emit Locked( msg.sender, _nftId, nftInfo[_nftId].tokenAmount, userLocks[msg.sender][_nftId].vestShare, userLocks[msg.sender][_nftId].vestPeriod, userLocks[msg.sender][_nftId].endTime, userLocks[msg.sender][_nftId].endTime );

    }


    function claimLock(uint256 _nftId) public nonReentrant {
        require(activeFeatures.vaultActive && 
                activeFeatures.giveNfts && 
                userLocks[msg.sender][_nftId].tokenAmount > 0 &&
                (userLocks[msg.sender][_nftId].tokenAmount - userLocks[msg.sender][_nftId].claimedAmount) > 0, 'Nothing to claim');
        

        // see how many vest points they have hit
        uint256 vested;
        for(uint256 i = 1; i <= nftInfo[_nftId].vestPoints; ++i){
            if(block.timestamp >= userLocks[msg.sender][_nftId].startTime + (userLocks[msg.sender][_nftId].vestPeriod * i)){    
                vested++;
            }
        }

        uint256 totalVested = userLocks[msg.sender][_nftId].vestShare * vested;

        // get the amount owed to them based on previous claims and current vesting period
        uint256 toClaim = totalVested - userLocks[msg.sender][_nftId].claimedAmount;

        require(toClaim > 0, 'Nothing to claim.');

        userLocks[msg.sender][_nftId].claimedAmount = userLocks[msg.sender][_nftId].claimedAmount + toClaim;

        // move the tokens
        tokenIds[nftInfo[_nftId].tokenId].safeTransfer(address(msg.sender), toClaim);
        
        emit Claimed(msg.sender, _nftId, toClaim);

        if(block.timestamp >= userLocks[msg.sender][_nftId].endTime){
            delete userLocks[msg.sender][_nftId];
            emit UnLocked(msg.sender,_nftId);
        }
        
    }

    // Trade tokens directly for share points at 6:1 rate
    function tokensForShares(uint256 _amount) public nonReentrant {
        require(activeFeatures.vaultActive && activeFeatures.burnTokens && tokenIds[1].balanceOf(msg.sender) >= _amount, "Not enough tokens");

        uint256 adjustedShares = adjustTokenShares(_amount);

        vaultContracts.minerContract.giveShares(msg.sender,adjustedShares * vaultSettings.tokenBurnMultiplier, true );
        
        vaultStats.totalTokensBurned = vaultStats.totalTokensBurned + _amount;

        tokenIds[1].safeTransferFrom(address(msg.sender),burnAddress, _amount);
        emit TokensBurned(msg.sender, _amount, adjustedShares * vaultSettings.tokenBurnMultiplier);
    }

    // give or burn an NFT
    function giveNft(uint256 _nftId, uint256 _amount) public nonReentrant {
        require(activeFeatures.vaultActive && activeFeatures.giveNfts && nftInfo[_nftId].sharePoints > 0  && !nftInfo[_nftId].isDisabled && vaultContracts.nftContract.balanceOf(address(msg.sender), _nftId) >= _amount ,'cant give');

        // require(isActive && nftInfo[_nftId].sharePoints > 0  && !nftInfo[_nftId].isDisabled, 'NFT Not Registered');

        address toSend = address(this);
        uint256 multiplier = vaultSettings.nftGiveMultiplier;

        // check if we hit the burn thresh
        if(nftInfo[_nftId].toBurn && (vaultContracts.nftContract.maxSupply(_nftId) - vaultContracts.nftContract.balanceOf(address(burnAddress), _nftId) ) <= vaultSettings.burnThresh){
            nftInfo[_nftId].toBurn = false;
        }
        

        //see if we burn it
        if(nftInfo[_nftId].toBurn){
            toSend = burnAddress;
            multiplier =  vaultSettings.nftBurnMultiplier;
            nftInfo[_nftId].burnedAmount = nftInfo[_nftId].burnedAmount + _amount;
        } else {
            // check if it's in packs
            if(inNftPacks[_nftId] && (vaultContracts.nftContract.balanceOf(address(this), _nftId) - nftInfo[_nftId].lockedNfts) >= vaultSettings.packThresh){
                toSend = address(vaultContracts.nftPacks);
            }
            // check if it's rewards
            if(inNftRewards[_nftId] && (vaultContracts.nftContract.balanceOf(address(this), _nftId) - nftInfo[_nftId].lockedNfts) >= vaultSettings.packThresh){
                toSend = address(vaultContracts.nftRewards);
            }
            nftInfo[_nftId].givenAmount = nftInfo[_nftId].givenAmount + _amount;
        }

        // give them shares for the NFTs
        uint256 adjustedShares = adjustNftShares(_nftId);
        vaultContracts.minerContract.giveShares(msg.sender, adjustedShares * _amount * multiplier, true );
        
        // send the NFT
        vaultContracts.nftContract.safeTransferFrom( msg.sender, toSend, _nftId, _amount, "");

        emit NftGiven(msg.sender, _nftId, _amount, adjustedShares * _amount * multiplier, nftInfo[_nftId].toBurn);

    }

    function adjustTokenShares(uint256 _amount) public view returns(uint256){
        return ((_calcAdjustedShares(vaultSettings.tokenShare, vaultSettings.tokenPercent) * _amount) * 10) / vaultSettings.shareMod;
    }

    function adjustNftShares(uint256 _nftId) public view returns(uint256) {
        return ((_calcAdjustedShares(nftInfo[_nftId].sharePoints, nftInfo[_nftId].sharePercent ) * 1 ether) * 10) / vaultSettings.shareMod;
    }

    function giveAdjustTokenShares(address _user, uint256 _amount) external {
        require(canGive[msg.sender], "Can't give");
        vaultContracts.minerContract.giveShares(_user, adjustTokenShares(_amount),false);
    }
    
    function calcAdjustedShares(uint256 _baseShares, uint256 _sharePercent) internal view returns(uint256) {
        return _calcAdjustedShares(_baseShares,_sharePercent);
    }

    function _calcAdjustedShares(uint256 _baseShares, uint256 _sharePercent) internal view returns(uint256) {
        uint256 totalVaultShares = vaultContracts.minerContract.getTotalShares();
        uint256 adjustedShares = (_sharePercent * totalVaultShares ) / 10000000;

        if(adjustedShares > _baseShares) {
            return adjustedShares;
        }
        return _baseShares;

    }

    // locks an NFT for the amount of time and the user share points
    // dont't allow burnable NFTS to count
    function lockNft(uint256 _nftId, uint256 _amount) public nonReentrant {
        require(
            activeFeatures.vaultActive && 
            activeFeatures.giveNfts && 
            nftInfo[_nftId].sharePoints > 0  && 
            !nftInfo[_nftId].toBurn && 
            !nftInfo[_nftId].isDisabled && 
            vaultContracts.nftContract.balanceOf(address(msg.sender), _nftId) >= _amount , "Can't Lock");
        // && userNftLocks[msg.sender][_nftId].startTime == 0
        
        // require(isActive && nftInfo[_nftId].sharePoints > 0  && !nftInfo[_nftId].toBurn && !nftInfo[_nftId].isDisabled, 'NFT Not Registered');

        userNftLocks[msg.sender][_nftId].amount = userNftLocks[msg.sender][_nftId].amount + _amount;
        userNftLocks[msg.sender][_nftId].startTime = block.timestamp; //  block.timestamp;
        userNftLocks[msg.sender][_nftId].endTime = block.timestamp + nftInfo[_nftId].lockDuration; // block.timestamp.add(nftInfo[_nftId].lockDuration);

        // update the locked count
        nftInfo[_nftId].lockedNfts = nftInfo[_nftId].lockedNfts + _amount;

        // give them shares for the NFTs 
        uint256 sp = adjustNftShares(_nftId) * _amount;

        userNftLocks[msg.sender][_nftId].sharePoints = userNftLocks[msg.sender][_nftId].sharePoints + sp;
        vaultContracts.minerContract.giveShares(msg.sender, sp, true);

        // send the NFT
        vaultContracts.nftContract.safeTransferFrom( msg.sender, address(this), _nftId, _amount, "");

        emit NftLocked( msg.sender, _nftId, _amount, sp, userNftLocks[msg.sender][_nftId].startTime, userNftLocks[msg.sender][_nftId].endTime);

    }

    // unlocks and claims an NFT if allowed and removes the share points
    function unLockNft(uint256 _nftId) public nonReentrant {
        require(activeFeatures.vaultActive && activeFeatures.giveNfts && userNftLocks[msg.sender][_nftId].amount > 0  && block.timestamp >= userNftLocks[msg.sender][_nftId].endTime, 'cant unlock');
        // require(block.timestamp >= userNftLocks[msg.sender][_nftId].endTime, 'Still Locked');
        
        // see if they have reset the account
        if(userNftLocks[msg.sender][_nftId].startTime > vaultContracts.minerContract.getLastReset(msg.sender)){
            // remove the shares
            vaultContracts.minerContract.removeShares(msg.sender, userNftLocks[msg.sender][_nftId].sharePoints);
        }

        uint256 amount = userNftLocks[msg.sender][_nftId].amount;
        delete userNftLocks[msg.sender][_nftId];
        // update the locked count
        nftInfo[_nftId].lockedNfts = nftInfo[_nftId].lockedNfts - amount;
        
        // send the NFTf
        vaultContracts.nftContract.safeTransferFrom(  address(this), msg.sender, _nftId, amount, "");

        emit NftUnLocked( msg.sender, _nftId, amount);
    }

    event NftUsed(address indexed user, uint256 nftId, uint256 nftType, uint256 newShares);
    function useNft(uint256 _nftId) public  nonReentrant{
        require(vaultContracts.minerContract.isInitialized() && activeFeatures.vaultActive && activeFeatures.useNft && vaultNftInfo[_nftId].nftType > 0 && vaultNftInfo[_nftId].nftType < 4 && !vaultNftInfo[_nftId].isDisabled && vaultContracts.nftContract.balanceOf(msg.sender,_nftId) > 0,'Cant Use');
        // require(!vaultNftInfo[_nftId].isDisabled,'NFT Disabled');
        // require(vaultContracts.nftContract.balanceOf(msg.sender,_nftId) > 0, 'No NFT Balance');

        // send the NFT
        // vaultContracts.nftContract.safeTransferFrom( msg.sender, address(this), _nftId, 1, "");
        
        // burn the NFT
       vaultContracts.nftContract.safeTransferFrom(msg.sender, burnAddress, _nftId, 1, "");
        

        uint256 newShares;
        // if the type is instant, give them instant shares
        if(vaultNftInfo[_nftId].nftType == 2){
            // direct amount
            newShares = vaultNftInfo[_nftId].amount;
            vaultContracts.minerContract.giveShares(msg.sender,newShares,true);
            // claimedWorkers[msg.sender] = vaultNftInfo[_nftId].amount * vaultContracts.minerContract.COST_FOR_SHARE();
            // vaultContracts.minerContract.vaultClaimWorkers(msg.sender,msg.sender);
        } else if(vaultNftInfo[_nftId].nftType == 3){
            // adjusted amount
            newShares = adjustTokenShares(vaultNftInfo[_nftId].amount);
            vaultContracts.minerContract.giveShares(msg.sender,newShares,true);
            // claimedWorkers[msg.sender] = adjustTokenShares(vaultNftInfo[_nftId].amount) * vaultContracts.minerContract.COST_FOR_SHARE();
            // vaultContracts.minerContract.vaultClaimWorkers(msg.sender,msg.sender,false);
        } else {
            // otherwise set the current multiplier    
            vaultContracts.minerContract.setCurrentMultiplier(
                msg.sender,
                _nftId,
                vaultNftInfo[_nftId].lifetime,
                block.timestamp,
                block.timestamp + vaultNftInfo[_nftId].lifetime,
                vaultNftInfo[_nftId].multiplier
            );
            /*
            currentMultiplier[msg.sender].nftId = _nftId;
            currentMultiplier[msg.sender].lifetime = vaultNftInfo[_nftId].lifetime;
            currentMultiplier[msg.sender].startTime = block.timestamp;
            currentMultiplier[msg.sender].endTime = block.timestamp + vaultNftInfo[_nftId].lifetime;
            currentMultiplier[msg.sender].multiplier = vaultNftInfo[_nftId].multiplier;
            */
        }

        emit NftUsed(msg.sender, _nftId, vaultNftInfo[_nftId].nftType, newShares );

    }

    //gets shares of an address
    function getShares(address _addr) public view returns(uint256){
        return vaultContracts.minerContract.getMyShares(_addr);
    }


    

    // // burn all mPCKT in the contract, this gets built up when adding LP
    // @TODO need to exclude locked tokens
    // function burnLeftovers() public onlyOwner {
    //     tokenIds[1].transferFrom(address(this), burnAddress, tokenIds[1].balanceOf(address(this)) );
    // }

/*    //swaps Native for a token
    function _swapNativeForToken(uint256 amount, IERC20 toToken, address toAddress) internal {
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
*/
    /*event OnVaultReceive(address indexed sender, uint256 amount, uint256 toHolders, uint256 toLp);
    receive() external payable {

        // @TODO
        // Check if it's coming from the gateway address
        // don't add LP (LP added to sidechains pool)

        // Send half to LP
        uint256 lpBal = msg.value / 2;
        uint256 shareBal = msg.value - lpBal;

        //if we have no shares 100% LP    
        uint256 totalVaultShares = vaultContracts.minerContract.getTotalShares();
        if(totalVaultShares <= 0){
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
            uint256 contractTokenBal = tokenIds[1].balanceOf(address(this));
           
            // do the swap
            _swapNativeForToken(nativeToSpend, tokenIds[1], address(this));

            //new balance
            uint256 tokenToPost = tokenIds[1].balanceOf(address(this)) - contractTokenBal;

            // add LP
            _addLiquidity(tokenToPost, nativeToPost);
        }

        emit OnVaultReceive(msg.sender, msg.value, shareBal, lpBal);
    }
*/
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure override returns(bytes4) {
      return 0xf23a6e61;
    }


    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns(bytes4) {
      return 0xbc197c81;
    }

    function supportsInterface(bytes4 interfaceID) public view virtual override returns (bool) {
      return  interfaceID == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
      interfaceID == 0x4e2312e0;      // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
    }


}

