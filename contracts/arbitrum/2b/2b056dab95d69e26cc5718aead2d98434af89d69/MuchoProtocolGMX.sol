/*                               %@@@@@@@@@@@@@@@@@(                              
                        ,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                        
                    /@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.                   
                 &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(                
              ,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@              
            *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            
           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
         &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*        
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&       
       @@@@@@@@@@@@@   #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   &@@@@@@@@@@@      
      &@@@@@@@@@@@    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.   @@@@@@@@@@,     
      @@@@@@@@@@&   .@@@@@@@@@@@@@@@@@&@@@@@@@@@&&@@@@@@@@@@@#   /@@@@@@@@@     
     &@@@@@@@@@@    @@@@@&                 %          @@@@@@@@,   #@@@@@@@@,    
     @@@@@@@@@@    @@@@@@@@%       &&        *@,       @@@@@@@@    @@@@@@@@%    
     @@@@@@@@@@    @@@@@@@@%      @@@@      /@@@.      @@@@@@@@    @@@@@@@@&    
     @@@@@@@@@@    &@@@@@@@%      @@@@      /@@@.      @@@@@@@@    @@@@@@@@/    
     .@@@@@@@@@@    @@@@@@@%      @@@@      /@@@.      @@@@@@@    &@@@@@@@@     
      @@@@@@@@@@@    @@@@&         @@        .@          @@@@.   @@@@@@@@@&     
       @@@@@@@@@@@.   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@    @@@@@@@@@@      
        @@@@@@@@@@@@.  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   @@@@@@@@@@@       
         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@        
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#         
            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           
              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             
                &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@/               
                   &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(                  
                       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#                      
                            /@@@@@@@@@@@@@@@@@@@@@@@*  */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./IMuchoProtocol.sol";
import "./IPriceFeed.sol";
import "./IMuchoRewardRouter.sol";
import "./IGLPRouter.sol";
import "./IRewardRouter.sol";
import "./IGLPPriceFeed.sol";
import "./IGLPVault.sol";
import "./MuchoRoles.sol";

contract MuchoProtocolGMX is IMuchoProtocol, MuchoRoles, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;


    function protocolName() public pure returns (string memory) {
        return "GMX delta-neutral strategy";
    }

    function protocolDescription() public pure returns (string memory) {
        return "Performs a delta neutral strategy against GLP yield from GMX protocol";
    }

    /*---------------------------Variables--------------------------------*/
    //Last time weights updated from GMX
    uint256 lastWeightUpdate;

    //Last time rewards collected and values refreshed
    uint256 public lastUpdate;

    //Desired weight (same GLP has) for every token
    mapping(address => uint256) glpWeight;

    /*---------------------------Parameters--------------------------------*/



    //GLP Yield APR from GMX --> used to estimate our APR
    uint256 public glpApr;
    function updateGlpApr(uint256 _apr) external onlyTraderOrAdmin{
        glpApr = _apr;
    }

    //GLP mint fee for weth --> used to estimate our APR
    uint256 public glpWethMintFee;
    function updateGlpWethMintFee(uint256 _fee) external onlyTraderOrAdmin{
        glpWethMintFee = _fee;
    }

    //List of allowed tokens
    EnumerableSet.AddressSet tokenList;
    function addToken(address _token) external onlyAdmin {
        tokenList.add(_token);
    }

    //Relation between a token and secondary for weight computing (eg. USDT and DAI can be secondary for USDC)
    mapping(address => EnumerableSet.AddressSet) tokenToSecondaryTokens;
    function addSecondaryToken(address _mainToken, address _secondary) external onlyAdmin { tokenToSecondaryTokens[_mainToken].add(_secondary);    }
    function removeSecondaryToken(address _mainToken, address _secondary) external onlyAdmin { tokenToSecondaryTokens[_mainToken].remove(_secondary);    }

    //Slippage we use when converting to GLP, to have a security gap with mint fees
    uint256 public slippage = 50;
    function setSlippage(uint256 _slippage) external onlyTraderOrAdmin {
        require(_slippage >= 10 && _slippage <= 1000, "not in range");
        slippage = _slippage;
    }

    //Address where we send the owner profit
    address public earningsAddress;
    function setEarningsAddress(address _earnings) external onlyAdmin {
        require(_earnings != address(0), "not valid");
        earningsAddress = _earnings;
    }

    //Claim esGmx, set false to save gas
    bool public claimEsGmx = false;
    function updateClaimEsGMX(bool _new) external onlyTraderOrAdmin {
        claimEsGmx = _new;
    }

     // Safety not-invested margin min and desired (2 decimals)
    uint256 public minNotInvestedPercentage = 250;
    function setMinNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, "MuchoProtocolGMX: minNotInvestedPercentage not in range");
        minNotInvestedPercentage = _percent;
    }
    uint256 public desiredNotInvestedPercentage = 500;
    function setDesiredNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, "MuchoProtocolGMX: desiredNotInvestedPercentage not in range");
        desiredNotInvestedPercentage = _percent;
    }

    //If variation against desired weight is less than this, do not move:
    uint256 public minBasisPointsMove = 100;
    function setMinWeightBasisPointsMove(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 500 && _percent > 0, "MuchoProtocolGMX: minBasisPointsMove not in range");
        minBasisPointsMove = _percent;
    }

    //Lapse to refresh weights when refreshing investment
    uint256 public maxRefreshWeightLapse = 1 days;
    function setMaxRefreshWeightLapse(uint256 _mw) external onlyTraderOrAdmin {
        require(_mw > 0, "MuchoProtocolGmx: Not valid lapse");
        maxRefreshWeightLapse = _mw;
    }

    //Manual mode for desired weights (in automatic, gets it from GLP Contract):
    bool public manualModeWeights = false;
    function setManualModeWeights(bool _manual) external onlyTraderOrAdmin {
        manualModeWeights = _manual;
    }

    //How do we split the rewards (percentages for owner and nft holders)
    RewardSplit public rewardSplit;
    function setRewardPercentages(RewardSplit calldata _split) external onlyTraderOrAdmin {
        require(_split.NftPercentage.add(_split.ownerPercentage) <= 10000, "MuchoProtocolGmx: NTF and owner fee are more than 100%");
        rewardSplit = RewardSplit({
            NftPercentage: _split.NftPercentage,
            ownerPercentage: _split.ownerPercentage
        });
    }

    //Protocol where we compound the profits
    IMuchoProtocol public compoundProtocol;
    function setCompoundProtocol(IMuchoProtocol _target) external onlyTraderOrAdmin {
        compoundProtocol = _target;
    }


    /*---------------------------Contracts--------------------------------*/

    //GMX tokens - escrowed GMX and staked GLP
    IERC20 public EsGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);
    function updateEsGMX(address _new) external onlyAdmin {
        EsGMX = IERC20(_new);
    }

    //Staked GLP
    IERC20 public fsGLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    function updatefsGLP(address _new) external onlyAdmin {
        fsGLP = IERC20(_new);
    }

    //WETH for the rewards
    IERC20 public WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    function updateWETH(address _new) external onlyAdmin {
        WETH = IERC20(_new);
    }

    //Interfaces to interact with GMX protocol

    //GLP Router:
    IGLPRouter public glpRouter = IGLPRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    function updateRouter(address _newRouter) external onlyAdmin {
        glpRouter = IGLPRouter(_newRouter);
    }

    //GLP Reward Router:
    IRewardRouter public glpRewardRouter = IRewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    function updateRewardRouter(address _newRouter) external onlyAdmin {
        glpRewardRouter = IRewardRouter(_newRouter);
    }

    //GLP Staking Pool address:
    address public poolGLP = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    function updatepoolGLP(address _newManager) external onlyAdmin {
        poolGLP = _newManager;
    }

    //GLP Vault
    IGLPVault public glpVault = IGLPVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    function updateGLPVault(address _newVault) external onlyAdmin {
        glpVault = IGLPVault(_newVault);
    }

    //MuchoRewardRouter Interaction for NFT Holders
    IMuchoRewardRouter public muchoRewardRouter = IMuchoRewardRouter(address(0));
    function setMuchoRewardRouter(address _contract) external onlyAdmin {
        muchoRewardRouter = IMuchoRewardRouter(_contract);
    }

    //GLP Price feed
    IGLPPriceFeed public priceFeed;
    function setPriceFeed(IGLPPriceFeed _feed) external onlyAdmin {
        priceFeed = _feed;
    }

    /*---------------------------Methods: trading interface--------------------------------*/

    //Updates weights, token investment, refreshes amounts and updates aprs:
    function refreshInvestment() external onlyOwnerTraderOrAdmin {
        //console.log("    SOL ***refreshInvestment function***");
        if (!manualModeWeights && block.timestamp.sub(lastWeightUpdate) > maxRefreshWeightLapse) {
            updateGlpWeights();
        }

        updateTokensInvestment();
    }

    //Cycles the rewards from GLP staking and compounds
    function cycleRewards() external onlyOwnerTraderOrAdmin {
        if (claimEsGmx) {
            glpRewardRouter.claimEsGmx();
            uint256 balanceEsGmx = EsGMX.balanceOf(address(this));
            if (balanceEsGmx > 0) glpRewardRouter.stakeEsGmx(balanceEsGmx);
        }
        cycleRewardsETH();
    }

    //Withdraws a token amount from the not invested part. Withdraws the maximum possible up to the desired amount
    function notInvestedTrySend(address _token, uint256 _amount, address _target) public onlyOwner returns (uint256) {
        IERC20 tk = IERC20(_token);
        uint256 balance = tk.balanceOf(address(this));
        uint256 amountToTransfer = _amount;
        if (balance < _amount) amountToTransfer = balance;

        tk.safeTransfer(_target, amountToTransfer);
        emit WithdrawnNotInvested(_token, _target, amountToTransfer, getTokenStaked(_token));
        return amountToTransfer;
    }

    //Withdraws a token amount from the invested part
    function withdrawAndSend(address _token, uint256 _amount, address _target) external onlyOwner nonReentrant {
        require(_amount <= getTokenInvested(_token), "Cannot withdraw more than invested");
        
        //Total GLP to unstake
        uint256 glpOut = tokenToGlp(_token, _amount).mul(10000 + slippage).div(glpWeight[_token]);

        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address tk = tokenList.at(i);
            uint256 glpToTk = glpOut.mul(glpWeight[tk]).div(10000);
            uint256 minReceive = (tk == _token) ? _amount : 0;
            swapGLPto(glpToTk, tk, minReceive);
        }

        IERC20(_token).safeTransfer(_target, _amount);
        emit WithdrawnInvested(_token, _target, _amount, getTokenStaked(_token));
    }

    //Notification from the HUB of a deposit
    function notifyDeposit(address _token, uint256 _amount) external onlyOwner nonReentrant {
        require(validToken(_token), "MuchoProtocolGMX.notifyDeposit: token not supported");
        //console.log("    SOL - MuchoProtocolGMX - notifyDeposit", _token, _amount, getTokenStaked(_token));
        emit DepositNotified(msg.sender, _token, _amount, getTokenStaked(_token));
    }

    //Expected APR with current investment
    function getExpectedAPR(address _token, uint256 _additionalAmount) external view returns(uint256){
        uint256 investedPctg = getTokenInvested(_token).add(_additionalAmount).mul(10000).div(getTokenStaked(_token));
        uint256 compoundPctg = 10000 - rewardSplit.NftPercentage - rewardSplit.ownerPercentage;
        return glpApr.mul(compoundPctg).mul(10000 - glpWethMintFee).mul(investedPctg).div(10**12);
    }


    /*---------------------------Methods: token handling--------------------------------*/

    //Sets manually the desired weight for a vault
    function setWeight(address _token, uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 7000 && _percent > 0, "MuchoProtocolGmx.setWeight: not in range");
        require(manualModeWeights, "MuchoProtocolGmx.setWeight: automatic mode");
        glpWeight[_token] = _percent;
    }

    //Updates desired weights from GLP in automatic mode:
    function updateGlpWeights() public onlyOwnerTraderOrAdmin {
        require(!manualModeWeights, "MuchoProtocolGmx: manual mode");

        // Store all USDG value (deposit + secondary tokens) for each vault, and total USDG amount to divide later
        uint256 totalUsdg;
        uint256[] memory glpUsdgs = new uint256[](tokenList.length());
        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            uint256 vaultUsdg = glpVault.usdgAmounts(token);

            for (uint j = 0; j < tokenToSecondaryTokens[token].length(); j = j.add(1)) {
                uint256 secUsdg = glpVault.usdgAmounts(tokenToSecondaryTokens[token].at(j));
                vaultUsdg = vaultUsdg.add(secUsdg);
            }

            glpUsdgs[i] = vaultUsdg;
            totalUsdg = totalUsdg.add(vaultUsdg);
        }

        // Calculate weights for every vault
        uint256 totalWeight = 0;
        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            uint256 vaultWeight = glpUsdgs[i].mul(10000).div(totalUsdg);
            glpWeight[token] = vaultWeight;
            totalWeight = totalWeight.add(vaultWeight);
        }

        // Check total weight makes sense
        uint256 diff = (totalWeight > 10000) ? (totalWeight - 10000) : (10000 - totalWeight);
        require(diff < 100, "MuchoProtocolGmx.updateDesiredWeightsFromGLP: Total weight far away from 1");

        //Update date
        lastWeightUpdate = block.timestamp;
    }



    /*----------------------------Public VIEWS to get the token amounts------------------------------*/

    
    function getDepositFee(address _token, uint256 _amount) external view returns(uint256){
        uint256 mbFee = glpVault.mintBurnFeeBasisPoints();
        uint256 taxFee = glpVault.taxBasisPoints();
        uint256 price = priceFeed.getPrice(_token);
        uint8 dec = IERC20Metadata(_token).decimals();
        uint256 usdgDelta = _amount.mul(10**(30+18-dec)).div(price);
        return glpVault.getFeeBasisPoints(_token, usdgDelta, mbFee, taxFee, true);
    }

    function getWithdrawalFee(address _token, uint256 _amount) external view returns(uint256){
        uint256 mbFee = glpVault.mintBurnFeeBasisPoints();
        uint256 taxFee = glpVault.taxBasisPoints();
        uint256 price = priceFeed.getPrice(_token);
        uint8 dec = IERC20Metadata(_token).decimals();
        uint256 usdgDelta = _amount.mul(10**(30+18-dec)).div(price);
        return glpVault.getFeeBasisPoints(_token, usdgDelta, mbFee, taxFee, false);
    }

    //Amount of token that is invested
    function getTokenInvested(address _token) public view returns (uint256) {
        return
            glpToToken(fsGLP.balanceOf(address(this)), _token)
                .mul(glpWeight[_token])
                .div(10000);
    }

    //Amount of token that is not invested
    function getTokenNotInvested(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    //Total Amount of token (invested + not)
    function getTokenStaked(address _token) public view returns (uint256) {
        return getTokenNotInvested(_token).add(getTokenInvested(_token));
    }

    //List of total Amount of token (invested + not) for all tokens
    function getAllTokensStaked() public view returns (address[] memory, uint256[] memory) {
        address[] memory tkOut = new address[](tokenList.length());
        uint256[] memory amOut = new uint256[](tokenList.length());
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tkOut[i] = tokenList.at(i);
            amOut[i] = getTokenStaked(tkOut[i]);
        }

        return (tkOut, amOut);
    }

    //USD value of token that is invested
    function getTokenUSDInvested(address _token) public view returns (uint256) {
        return glpToUsd(fsGLP.balanceOf(address(this))).mul(glpWeight[_token]).div(10000);
    }

    //USD value of token that is NOT invested
    function getTokenUSDNotInvested(address _token) public view returns (uint256) {
        return tokenToUsd(_token, getTokenNotInvested(_token));
    }

    //Total USD value of token (invested + not)
    function getTokenUSDStaked(address _token) public view returns (uint256) {
        return tokenToUsd(_token, getTokenStaked(_token));
    }

    //Desired weight for a token vault
    function getTokenWeight(address _token) external view returns (uint256) {
        return glpWeight[_token];
    }

    //Total USD value (invested + not)
    function getTotalUSD() external view returns (uint256) {
        (uint256 totalUsd, , ) = getTotalUSDWithTokensUsd();
        return totalUsd;
    }

    //Invested USD value for all tokens
    function getTotalInvestedUSD() external view returns (uint256) {
        uint256 tInvested = 0;
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tInvested = tInvested.add(getTokenUSDInvested(tokenList.at(i)));
        }

        return tInvested;
    }

    //Total USD value for all tokens + lists of total usd and invested usd for each token
    function getTotalUSDWithTokensUsd() public view returns (uint256, uint256[] memory, uint256[] memory){
        uint256 totalUsd = 0;
        uint256[] memory tokenUsds = new uint256[](tokenList.length());
        uint256[] memory tokenInvestedUsds = new uint256[](tokenList.length());

        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            uint256 staked = getTokenUSDStaked(token);
            tokenUsds[i] = staked;
            tokenInvestedUsds[i] = getTokenUSDInvested(token);
            totalUsd = totalUsd.add(tokenUsds[i]);
        }

        return (totalUsd, tokenUsds, tokenInvestedUsds);
    }

    

    /*---------------------------INTERNAL Methods--------------------------------*/

    //Updates the investment part for each token according to the desired weights
    function updateTokensInvestment() internal {
        (uint256 totalUsd, uint256[] memory tokenUsd, uint256[] memory tokenInvestedUsd) = getTotalUSDWithTokensUsd();

        //Only can do delta neutral if all tokens are present
        if(tokenUsd[0] == 0 || tokenUsd[1] == 0 || tokenUsd[2] == 0){
            return;
        }

        (address minTokenByWeight, uint256 minTokenUsd) = getMinTokenByWeight(totalUsd, tokenUsd);

        //Calculate and do move for the minimum weight token
        doMinTokenWeightMove(minTokenByWeight);

        //Calc new total USD
        uint256 newTotalInvestedUsd = minTokenUsd
            .mul(10000 - desiredNotInvestedPercentage)
            .div(glpWeight[minTokenByWeight]);

        //Calculate move for every token different from the main one:
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);

            if (token != minTokenByWeight) {
                doNotMinTokenMove(token, tokenUsd[i], tokenInvestedUsd[i], newTotalInvestedUsd.mul(glpWeight[token]).div(10000) );
            }
        }

        lastUpdate = block.timestamp;
    }

    //Gets the token more far away from the desired weight, will be the one more invested and will point our global investment position
    function getMinTokenByWeight(uint256 _totalUsd, uint256[] memory _tokenUsd) internal view returns (address, uint256) {
        uint maxDiff = 0;
        uint256 minUsd;
        address minToken;

        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            if (glpWeight[token] > _tokenUsd[i].mul(10000).div(_totalUsd)) {
                uint diff = _totalUsd
                    .mul(glpWeight[token])
                    .div(_tokenUsd[i])
                    .sub(10000); //glpWeight[token].sub(_tokenUsd[i].mul(10000).div(_totalUsd));
                if (diff > maxDiff) {
                    minToken = token;
                    minUsd = _tokenUsd[i];
                    maxDiff = diff;
                }
            }
        }

        return (minToken, minUsd);
    }

    //Moves the min token to the desired min invested percentage
    function doMinTokenWeightMove(address _minTokenByWeight) internal {
        uint256 totalBalance = getTokenStaked(_minTokenByWeight);
        uint256 notInvestedBalance = getTokenNotInvested(_minTokenByWeight);
        uint256 notInvestedBP = notInvestedBalance.mul(10000).div(totalBalance);

        //Invested less than desired:
        if (notInvestedBP > desiredNotInvestedPercentage && notInvestedBP.sub(desiredNotInvestedPercentage) > minBasisPointsMove) {
            uint256 amountToMove = notInvestedBalance.sub(
                desiredNotInvestedPercentage.mul(totalBalance).div(10000)
            );
            swaptoGLP(amountToMove, _minTokenByWeight);
        }
        //Invested more than desired:
        else if (notInvestedBP < minNotInvestedPercentage) {
            uint256 glpAmount = tokenToGlp(_minTokenByWeight, desiredNotInvestedPercentage.mul(totalBalance).div(10000).sub(notInvestedBalance) );
            swapGLPto(glpAmount, _minTokenByWeight, 0);
        }
    }

    //Moves a token which is not the min
    function doNotMinTokenMove(address _token, uint256 _totalTokenUSD, uint256 _currentUSDInvested, uint256 _newUSDInvested) internal {
        //Invested less than desired:
        if (_newUSDInvested > _currentUSDInvested && _newUSDInvested.sub(_currentUSDInvested).mul(10000).div(_totalTokenUSD) > minBasisPointsMove) {
            uint256 amountToMove = usdToToken(_newUSDInvested.sub(_currentUSDInvested), _token);
            swaptoGLP(amountToMove, _token);
        }

        //Invested more than desired:
        else if (_newUSDInvested < _currentUSDInvested && _currentUSDInvested.sub(_newUSDInvested).mul(10000).div(_currentUSDInvested) > minBasisPointsMove) {
            uint256 glpAmount = usdToGlp(_currentUSDInvested.sub(_newUSDInvested));
            swapGLPto(glpAmount, _token, 0);
        }
    }

    //Get WETH rewards and distribute among the vaults and owner
    function cycleRewardsETH() private {
        uint256 wethInit = WETH.balanceOf(address(this));

        //claim weth fees
        glpRewardRouter.claimFees();
        uint256 rewards = WETH.balanceOf(address(this)).sub(wethInit);

        if(rewards > 0){
            //use compoundPercentage to calculate the total amount and swap to GLP
            uint256 compoundAmount = rewards.mul(10000 - rewardSplit.NftPercentage - rewardSplit.ownerPercentage).div(10000);
            if (compoundProtocol == this) {
                swaptoGLP(compoundAmount, address(WETH));
            } else {
                notInvestedTrySend(address(WETH), compoundAmount, address(compoundProtocol));
            }

            //use stakersPercentage to calculate the amount for rewarding stakers
            uint256 stakersAmount = rewards.mul(rewardSplit.NftPercentage).div(10000);
            WETH.approve(address(muchoRewardRouter), stakersAmount);
            muchoRewardRouter.depositRewards(address(WETH), stakersAmount);

            //send the rest to admin
            uint256 adminAmount = rewards.sub(compoundAmount).sub(stakersAmount);
            WETH.safeTransfer(earningsAddress, adminAmount);
        }
    }

    //Validates a token
    function validToken(address _token) internal view returns (bool) {
        if (tokenList.contains(_token)) return true;

        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            if (tokenToSecondaryTokens[tokenList.at(i)].contains(_token))
                return true;
        }
        return false;
    }


    /*----------------------------Internal token conversion methods------------------------------*/

    function tokenToGlp(address _token, uint256 _amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return
            _amount
                .mul(priceFeed.getPrice(_token))
                .div(priceFeed.getGLPprice())
                .mul(10 ** glpDecimals)
                .div(10 ** decimals);
    }

    function glpToToken(uint256 _amountGlp, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return
            _amountGlp
                .mul(priceFeed.getGLPprice())
                .div(priceFeed.getPrice(_token))
                .mul(10 ** decimals)
                .div(10 ** glpDecimals);
    }

    function tokenToUsd(address _token, uint256 _amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _amount.mul(priceFeed.getPrice(_token)).div(10 ** (30 - 18 + decimals));
    }

    function usdToToken(uint256 _usdAmount, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _usdAmount.mul(10 ** (30 - 18 + decimals)).div(priceFeed.getPrice(_token));
    }

    function usdToGlp(uint256 _usdAmount) internal view returns (uint256) {
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();
        return _usdAmount.mul(10 ** (30 + glpDecimals - 18)).div(priceFeed.getGLPprice());
    }

    function glpToUsd(uint256 _glpAmount) internal view returns (uint256) {
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return _glpAmount.mul(priceFeed.getGLPprice()).div(10 ** (30 + glpDecimals - 18));
    }



    /*----------------------------GLP mint and token conversion------------------------------*/

    function swapGLPto( uint256 _amountGlp, address token, uint256 min_receive) private returns (uint256) {
        return
            glpRouter.unstakeAndRedeemGlp(
                token,
                _amountGlp,
                min_receive,
                address(this)
            );
    }

    //Mint GLP from token
    function swaptoGLP(uint256 _amount, address token) private returns (uint256) {
        IERC20(token).safeIncreaseAllowance(poolGLP, _amount);
        uint256 resGlp = glpRouter.mintAndStakeGlp(token, _amount, 0, 0);

        return resGlp;
    }
}

