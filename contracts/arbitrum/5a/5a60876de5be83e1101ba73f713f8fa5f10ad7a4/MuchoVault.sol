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
import "./IMuchoVault.sol";
import "./IMuchoHub.sol";
import "./IMuchoBadgeManager.sol";
import "./IPriceFeed.sol";
import "./MuchoRoles.sol";
import "./UintSafe.sol";

contract MuchoVault is IMuchoVault, MuchoRoles, ReentrancyGuard{

    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint8;
    using UintSafe for uint256;

    VaultInfo[] private vaultInfo;

    /*-------------------------TYPES---------------------------------------------*/
    // Same (special fee) for MuchoBadge NFT holders:
    struct MuchoBadgeSpecialFee{  
        uint256 fee;  
        bool exists; 
    }

    /*--------------------------CONTRACTS---------------------------------------*/

    //HUB for handling investment in the different protocols:
    IMuchoHub public muchoHub = IMuchoHub(0x0000000000000000000000000000000000000000);
    function setMuchoHub(address _contract) external onlyAdmin{ 
        muchoHub = IMuchoHub(_contract);
        emit MuchoHubChanged(_contract); 
    }

    //Price feed to calculate USD values:
    IPriceFeed public priceFeed = IPriceFeed(0x0000000000000000000000000000000000000000);
    function setPriceFeed(address _contract) external onlyAdmin{ 
        priceFeed = IPriceFeed(_contract);
        emit PriceFeedChanged(_contract); 
    }

    //Badge Manager to get NFT holder attributes:
    IMuchoBadgeManager public badgeManager = IMuchoBadgeManager(0xC439d29ee3C7fa237da928AD3A3D6aEcA9aA0717);
    function setBadgeManager(address _contract) external onlyAdmin { 
        badgeManager = IMuchoBadgeManager(_contract);
        emit BadgeManagerChanged(_contract);
    }

    //Address where we send profits from fees:
    address public earningsAddress;
    function setEarningsAddress(address _addr) external onlyAdmin{ 
        earningsAddress = _addr; 
        emit EarningsAddressChanged(_addr);
    }


    /*--------------------------PARAMETERS--------------------------------------*/

    //Fee (basic points) we will charge for swapping between mucho tokens:
    uint256 public bpSwapMuchoTokensFee = 25;
    function setSwapMuchoTokensFee(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 1000 && _percent >= 0, "not in range");
        bpSwapMuchoTokensFee = _percent;
        emit SwapMuchoTokensFeeChanged(_percent);
    }

    //Special fee with discount for swapping, for NFT holders. Each plan can have its own fee, otherwise will use the default one for no-NFT holders.
    mapping(uint256 => MuchoBadgeSpecialFee) public bpSwapMuchoTokensFeeForBadgeHolders;
    function setSwapMuchoTokensFeeForPlan(uint256 _planId, uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 1000 && _percent >= 0, "not in range");
        require(_planId > 0, "not valid plan");
        bpSwapMuchoTokensFeeForBadgeHolders[_planId] = MuchoBadgeSpecialFee({fee : _percent, exists: true});
        emit SwapMuchoTokensFeeForPlanChanged(_planId, _percent);
    }
    function removeSwapMuchoTokensFeeForPlan(uint256 _planId) external onlyTraderOrAdmin {
        require(_planId > 0, "not valid plan");
        bpSwapMuchoTokensFeeForBadgeHolders[_planId].exists = false;
        emit SwapMuchoTokensFeeForPlanRemoved(_planId);
    }

    //Maximum amount a user with NFT Plan can invest
    mapping(uint256 => mapping(uint256 => uint256)) maxDepositUserPlan;
    function setMaxDepositUserForPlan(uint256 _vaultId, uint256 _planId, uint256 _amount) external onlyTraderOrAdmin{
        maxDepositUserPlan[_vaultId][_planId] = _amount;
    }

    /*---------------------------------MODIFIERS and CHECKERS---------------------------------*/
    //Validates a vault ID
    modifier validVault(uint _id){
        require(_id < vaultInfo.length, "MuchoVaultV2.validVault: not valid vault id");
        _;
    }

    //Checks if there is a vault for the specified token
    function checkDuplicate(IERC20 _depositToken, IMuchoToken _muchoToken) internal view returns(bool) {
        for (uint256 i = 0; i < vaultInfo.length; ++i){
            if (vaultInfo[i].depositToken == _depositToken || vaultInfo[i].muchoToken == _muchoToken){
                return false;
            }        
        }
        return true;
    }

    /*----------------------------------VAULTS SETUP FUNCTIONS-----------------------------------------*/

    //Adds a vault:
    function addVault(IERC20Metadata _depositToken, IMuchoToken _muchoToken) external onlyAdmin returns(uint8){
        require(checkDuplicate(_depositToken, _muchoToken), "MuchoVaultV2.addVault: vault for that deposit or mucho token already exists");
        require(_depositToken.decimals() == _muchoToken.decimals(), "MuchoVaultV2.addVault: deposit and mucho token decimals cannot differ");

        vaultInfo.push(VaultInfo({
            depositToken: _depositToken,
            muchoToken: _muchoToken,
            totalStaked:0,
            stakedFromDeposits:0,
            lastUpdate: block.timestamp, 
            stakable: false,
            depositFee: 0,
            withdrawFee: 0,
            maxDepositUser: 10**30,
            maxCap: 0
        }));

        emit VaultAdded(_depositToken, _muchoToken);

        return uint8(vaultInfo.length.sub(1));
    }

    //Sets maximum amount to deposit:
    function setMaxCap(uint8 _vaultId, uint256 _max) external onlyTraderOrAdmin validVault(_vaultId){
        vaultInfo[_vaultId].maxCap = _max;
    }

    //Sets maximum amount to deposit for a user:
    function setMaxDepositUser(uint8 _vaultId, uint256 _max) external onlyTraderOrAdmin validVault(_vaultId){
        vaultInfo[_vaultId].maxDepositUser = _max;
    }

    //Sets a deposit fee for a vault:
    function setDepositFee(uint8 _vaultId, uint16 _fee) external onlyTraderOrAdmin validVault(_vaultId){
        require(_fee < 500, "MuchoVault: Max deposit fee exceeded");
        vaultInfo[_vaultId].depositFee = _fee;
        emit DepositFeeChanged(_vaultId, _fee);
    }

    //Sets a withdraw fee for a vault:
    function setWithdrawFee(uint8 _vaultId, uint16 _fee) external onlyTraderOrAdmin validVault(_vaultId){
        require(_fee < 100, "MuchoVault: Max withdraw fee exceeded");
        vaultInfo[_vaultId].withdrawFee = _fee;
        emit WithdrawFeeChanged(_vaultId, _fee);
    }

    //Opens or closes a vault for deposits:
    function setOpenVault(uint8 _vaultId, bool open) public onlyTraderOrAdmin validVault(_vaultId) {
        vaultInfo[_vaultId].stakable = open;
        if(open)
            emit VaultOpen(_vaultId);
        else
            emit VaultClose(_vaultId);
    }

    //Opens or closes ALL vaults for deposits:
    function setOpenAllVault(bool open) external onlyTraderOrAdmin {
        for (uint8 _vaultId = 0; _vaultId < vaultInfo.length; ++ _vaultId){
            setOpenVault(_vaultId, open);
        }
    }

    // Updates the totalStaked amount and refreshes apr (if it's time) in a vault:
    function updateVault(uint8 _vaultId) public onlyTraderOrAdmin validVault(_vaultId)  {
        _updateVault(_vaultId);
    }

    
    // Updates the totalStaked amount and refreshes apr (if it's time) in a vault:
    function _updateVault(uint8 _vaultId) internal   {
        //Update total staked
        vaultInfo[_vaultId].lastUpdate = block.timestamp;
        uint256 beforeStaked = vaultInfo[_vaultId].totalStaked;
        vaultInfo[_vaultId].totalStaked = muchoHub.getTotalStaked(address(vaultInfo[_vaultId].depositToken));

        emit VaultUpdated(_vaultId, beforeStaked, vaultInfo[_vaultId].totalStaked);
    }

    // Updates all vaults:
    function updateAllVaults() public onlyTraderOrAdmin {
        for (uint8 _vaultId = 0; _vaultId < vaultInfo.length; ++ _vaultId){
            updateVault(_vaultId);
        }
    }

    // Refresh Investment and update all vaults:
    function refreshAndUpdateAllVaults() external onlyTraderOrAdmin {
        muchoHub.refreshAllInvestments();
        updateAllVaults();
    }

    /*----------------------------Swaps between muchoTokens handling------------------------------*/

    //Gets the number of tokens user will get from a mucho swap:
    function getSwap(uint8 _sourceVaultId, uint256 _amountSourceMToken, uint8 _destVaultId) external view
                     validVault(_sourceVaultId) validVault(_destVaultId) returns(uint256) {
        //console.log("    SOL***getSwap***", _sourceVaultId, _amountSourceMToken, _destVaultId);
        require(_amountSourceMToken > 0, "MuchoVaultV2.swapMuchoToken: Insufficent amount");

        uint256 ownerAmount = getSwapFee(msg.sender).mul(_amountSourceMToken).div(10000);
        //console.log("    SOL - ownerAmount", ownerAmount);
        uint256 destOutAmount = 
                    getDestinationAmountMuchoTokenExchange(_sourceVaultId, _destVaultId, _amountSourceMToken, ownerAmount);

        return destOutAmount;
    }

    //Performs a muchoTokens swap
    function swap(uint8 _sourceVaultId, uint256 _amountSourceMToken, uint8 _destVaultId, uint256 _amountOutExpected, uint16 _maxSlippage) external
                     validVault(_sourceVaultId) validVault(_destVaultId) nonReentrant {

        require(_amountSourceMToken > 0, "MuchoVaultV2.swap: Insufficent amount");
        require(_maxSlippage < 10000, "MuchoVaultV2.swap: Maxslippage is not valid");
        IMuchoToken sMToken = vaultInfo[_sourceVaultId].muchoToken;
        IMuchoToken dMToken = vaultInfo[_destVaultId].muchoToken;
        require(sMToken.balanceOf(msg.sender) >= _amountSourceMToken, "MuchoVaultV2.swap: Not enough balance");
        require(_amountSourceMToken < sMToken.totalSupply().div(10), "MuchoVaultV2.swap: cannot swap more than 10% of total source");

        uint256 sourceOwnerAmount = getSwapFee(msg.sender).mul(_amountSourceMToken).div(10000);
        uint256 destOutAmount = 
                    getDestinationAmountMuchoTokenExchange(_sourceVaultId, _destVaultId, _amountSourceMToken, sourceOwnerAmount);

        require(destOutAmount > 0, "MuchoVaultV2.swap: user would get nothing");
        require(destOutAmount >= _amountOutExpected.mul(10000 - _maxSlippage).div(10000), "MuchoVaultV2.swap: Max slippage exceeded");
        require(destOutAmount < dMToken.totalSupply().div(10), "MuchoVaultV2.swap: cannot swap more than 10% of total destination");
        require(destOutAmount < vaultInfo[_destVaultId].stakedFromDeposits.div(3), "MuchoVaultV2.swap: cannot swap more than 33% of destination vault staked from deposits");

        //Move staked token
        {
            uint256 destIncreaseOrigToken = destOutAmount.mul(vaultInfo[_destVaultId].totalStaked).div(dMToken.totalSupply());
            vaultInfo[_destVaultId].totalStaked = vaultInfo[_destVaultId].totalStaked.add(destIncreaseOrigToken);
            vaultInfo[_destVaultId].stakedFromDeposits = vaultInfo[_destVaultId].stakedFromDeposits.add(destIncreaseOrigToken);
        }
        {
            uint256 sourceDecreaseOrigToken = _amountSourceMToken.sub(sourceOwnerAmount).mul(vaultInfo[_sourceVaultId].totalStaked);
            sourceDecreaseOrigToken = sourceDecreaseOrigToken.div(sMToken.totalSupply());
            //console.log("    SOL - sourceDecreaseOrigToken", sourceDecreaseOrigToken);
            //console.log("    SOL - vaultInfo[_sourceVaultId].totalStaked", vaultInfo[_sourceVaultId].totalStaked);
            require(sourceDecreaseOrigToken < vaultInfo[_sourceVaultId].totalStaked.div(10), "Cannot subtract more than 10% of total staked in source");
            require(sourceDecreaseOrigToken < vaultInfo[_sourceVaultId].stakedFromDeposits.div(3), "Cannot subtract more than 33% of deposit staked in source");
            vaultInfo[_sourceVaultId].totalStaked = vaultInfo[_sourceVaultId].totalStaked.sub(sourceDecreaseOrigToken);
            vaultInfo[_sourceVaultId].stakedFromDeposits = vaultInfo[_sourceVaultId].stakedFromDeposits.sub(sourceDecreaseOrigToken);
        }

        //Send fee to protocol owner
        if(sourceOwnerAmount > 0)
            sMToken.mint(earningsAddress, sourceOwnerAmount);
        
        //Send result to user
        dMToken.mint(msg.sender, destOutAmount);

        sMToken.burn(msg.sender, _amountSourceMToken);

        emit Swapped(msg.sender, _sourceVaultId, _amountSourceMToken, _destVaultId, _amountOutExpected, destOutAmount, sourceOwnerAmount);
        //console.log("    SOL - Burnt", _amountSourceMToken);
    }

    /*----------------------------CORE: User deposit and withdraw------------------------------*/
    
    //Deposits an amount in a vault
    function deposit(uint8 _vaultId, uint256 _amount) external validVault(_vaultId) nonReentrant {
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        IERC20 dToken = vaultInfo[_vaultId].depositToken;


        /*console.log("    SOL - DEPOSITING");
        console.log("    SOL - Sender and balance", msg.sender, dToken.balanceOf(msg.sender));
        console.log("    SOL - amount", _amount);*/
        
        require(_amount != 0, "MuchoVaultV2.deposit: Insufficent amount");
        require(msg.sender != address(0), "MuchoVaultV2.deposit: address is not valid");
        require(_amount <= dToken.balanceOf(msg.sender), "MuchoVaultV2.deposit: balance too low" );
        require(vaultInfo[_vaultId].stakable, "MuchoVaultV2.deposit: not stakable");
        require(vaultInfo[_vaultId].maxCap == 0 || vaultInfo[_vaultId].maxCap >= _amount.add(vaultInfo[_vaultId].totalStaked), "MuchoVaultV2.deposit: depositing more than max allowed in total");
        uint256 wantedDeposit = _amount.add(investorVaultTotalStaked(_vaultId, msg.sender));
        require(wantedDeposit <= investorMaxAllowedDeposit(_vaultId, msg.sender), "MuchoVaultV2.deposit: depositing more than max allowed per user");
     
        // Gets the amount of deposit token locked in the contract
        uint256 totalStakedTokens = vaultInfo[_vaultId].totalStaked;

        // Gets the amount of muchoToken in existence
        uint256 totalShares = mToken.totalSupply();

        // Remove the deposit fee and calc amount after fee
        uint256 ownerDepositFee = _amount.mul(vaultInfo[_vaultId].depositFee).div(10000);
        uint256 amountAfterFee = _amount.sub(ownerDepositFee);

        /*console.log("    SOL - depositFee", vaultInfo[_vaultId].depositFee);
        console.log("    SOL - ownerDepositFee", ownerDepositFee);
        console.log("    SOL - amountAfterFee", amountAfterFee);*/

        // If no muchoToken exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalStakedTokens == 0) {
            mToken.mint(msg.sender, amountAfterFee);
        } 
        // Calculate and mint the amount of muchoToken the depositToken is worth. The ratio will change overtime with APR
        else {
            uint256 what = amountAfterFee.mul(totalShares).div(totalStakedTokens);
            mToken.mint(msg.sender, what);
        }
        
        vaultInfo[_vaultId].totalStaked = vaultInfo[_vaultId].totalStaked.add(amountAfterFee);
        vaultInfo[_vaultId].stakedFromDeposits = vaultInfo[_vaultId].stakedFromDeposits.add(amountAfterFee);

        //console.log("    SOL - TOTAL STAKED AFTER DEP 0", vaultInfo[_vaultId].totalStaked);
        //console.log("    SOL - EXECUTING DEPOSIT FROM IN HUB");
        muchoHub.depositFrom(msg.sender, address(dToken), amountAfterFee, ownerDepositFee, earningsAddress);
        //console.log("    SOL - TOTAL STAKED AFTER DEP 1", vaultInfo[_vaultId].totalStaked);
        //console.log("    SOL - EXECUTING UPDATE VAULT");
        _updateVault(_vaultId);
        //console.log("    SOL - TOTAL STAKED AFTER DEP 2", vaultInfo[_vaultId].totalStaked);

        emit Deposited(msg.sender, _vaultId, _amount, vaultInfo[_vaultId].totalStaked);
    }

    //Withdraws from a vault. The user should have muschoTokens that will be burnt
    function withdraw(uint8 _vaultId, uint256 _share) external validVault(_vaultId) nonReentrant {
        //console.log("    SOL - WITHDRAW!!!");

        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        IERC20 dToken = vaultInfo[_vaultId].depositToken;

        require(_share != 0, "MuchoVaultV2.withdraw: Insufficient amount");
        require(msg.sender != address(0), "MuchoVaultV2.withdraw: address is not valid");
        require(_share <= mToken.balanceOf(msg.sender), "MuchoVaultV2.withdraw: balance too low");

        // Calculates the amount of depositToken the muchoToken is worth
        uint256 amountOut = _share.mul(vaultInfo[_vaultId].totalStaked).div(mToken.totalSupply());

        vaultInfo[_vaultId].totalStaked = vaultInfo[_vaultId].totalStaked.sub(amountOut);
        vaultInfo[_vaultId].stakedFromDeposits = vaultInfo[_vaultId].stakedFromDeposits.sub(amountOut);
        mToken.burn(msg.sender, _share);

        // Calculates withdraw fee:
        uint256 ownerWithdrawFee = amountOut.mul(vaultInfo[_vaultId].withdrawFee).div(10000);
        amountOut = amountOut.sub(ownerWithdrawFee);

        //console.log("    SOL - amountOut, ownerFee", amountOut, ownerWithdrawFee);

        muchoHub.withdrawFrom(msg.sender, address(dToken), amountOut, ownerWithdrawFee, earningsAddress);
        _updateVault(_vaultId);


        emit Withdrawn(msg.sender, _vaultId, amountOut, _share, vaultInfo[_vaultId].totalStaked);
    }


    /*---------------------------------INFO VIEWS---------------------------------------*/

    //Gets the deposit fee amount, adding owner's deposit fee (in this contract) + protocol's one
    function getDepositFee(uint8 _vaultId, uint256 _amount) external view returns(uint256){
        uint256 fee = _amount.mul(vaultInfo[_vaultId].depositFee).div(10000);
        return fee.add(muchoHub.getDepositFee(address(vaultInfo[_vaultId].depositToken), _amount.sub(fee)));
    }

    //Gets the withdraw fee amount, adding owner's withdraw fee (in this contract) + protocol's one
    function getWithdrawalFee(uint8 _vaultId, uint256 _amount) external view returns(uint256){
        uint256 fee = muchoHub.getWithdrawalFee(address(vaultInfo[_vaultId].depositToken), _amount);
        return fee.add(_amount.sub(fee).mul(vaultInfo[_vaultId].withdrawFee).div(10000));
    }

    //Gets the expected APR if we add an amount of token
    function getExpectedAPR(uint8 _vaultId, uint256 _additionalAmount) external view returns(uint256){
        return muchoHub.getExpectedAPR(address(vaultInfo[_vaultId].depositToken), _additionalAmount);
    }

    //Displays total amount of staked tokens in a vault:
    function vaultTotalStaked(uint8 _vaultId) validVault(_vaultId) external view returns(uint256) {
        return vaultInfo[_vaultId].totalStaked;
    }

    //Displays total amount of staked tokens from deposits (excluding profit) in a vault:
    function vaultStakedFromDeposits(uint8 _vaultId) validVault(_vaultId) external view returns(uint256) {
        return vaultInfo[_vaultId].stakedFromDeposits;
    }

    //Displays total amount a user has staked in a vault:
    function investorVaultTotalStaked(uint8 _vaultId, address _address) validVault(_vaultId) public view returns(uint256) {
        require(_address != address(0), "MuchoVaultV2.displayStakedBalance: No valid address");
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 totalShares = mToken.totalSupply();
        if(totalShares == 0) return 0;
        uint256 amountOut = mToken.balanceOf(_address).mul(vaultInfo[_vaultId].totalStaked).div(totalShares);
        return amountOut;
    }

    //Maximum amount of token allowed to deposit for user:
    function investorMaxAllowedDeposit(uint8 _vaultId, address _user) validVault(_vaultId) public view returns(uint256){
        uint256 maxAllowed = vaultInfo[_vaultId].maxDepositUser;
        IMuchoBadgeManager.Plan[] memory plans = badgeManager.activePlansForUser(_user);
        for(uint i = 0; i < plans.length; i = i.add(1)){
            uint256 id = plans[i].id;
            if(maxDepositUserPlan[_vaultId][id] > maxAllowed)
                maxAllowed = maxDepositUserPlan[_vaultId][id];
        }

        return maxAllowed;
    }

    //Price Muchotoken vs "real" token:
    function muchoTokenToDepositTokenPrice(uint8 _vaultId) validVault(_vaultId) external view returns(uint256) {
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 totalShares = mToken.totalSupply();
        uint256 amountOut = (vaultInfo[_vaultId].totalStaked).mul(10**18).div(totalShares);
        return amountOut;
    }

    //Total USD in a vault (18 decimals):
    function vaultTotalUSD(uint8 _vaultId) validVault(_vaultId) public view returns(uint256) {
         return getUSD(vaultInfo[_vaultId].depositToken, vaultInfo[_vaultId].totalStaked);
    }

    //Total USD an investor has in a vault:
    function investorVaultTotalUSD(uint8 _vaultId, address _user) validVault(_vaultId) public view returns(uint256) {
        require(_user != address(0), "MuchoVaultV2.totalUserVaultUSD: Invalid address");
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 mTokenUser = mToken.balanceOf(_user);
        uint256 mTokenTotal = mToken.totalSupply();

        if(mTokenUser == 0 || mTokenTotal == 0)
            return 0;

        return getUSD(vaultInfo[_vaultId].depositToken, vaultInfo[_vaultId].totalStaked.mul(mTokenUser).div(mTokenTotal));
    }

    //Total USD an investor has in all vaults:
    function investorTotalUSD(address _user) public view returns(uint256){
        require(_user != address(0), "MuchoVaultV2.totalUserUSD: Invalid address");
        uint256 total = 0;
         for (uint8 i = 0; i < vaultInfo.length; ++i){
            total = total.add(investorVaultTotalUSD(i, _user));
         }

         return total;
    }

    //Protocol TVL in USD:
    function allVaultsTotalUSD() public view returns(uint256) {
         uint256 total = 0;
         for (uint8 i = 0; i < vaultInfo.length; ++i){
            total = total.add(vaultTotalUSD(i));
         }

         return total;
    }

    //Gets a vault descriptive:
    function getVaultInfo(uint8 _vaultId) external view validVault(_vaultId) returns(VaultInfo memory){
        return vaultInfo[_vaultId];
    }
    

    /*-----------------------------------SWAP MUCHOTOKENS--------------------------------------*/

    //gets usd amount with 18 decimals for a erc20 token and amount
    function getUSD(IERC20Metadata _token, uint256 _amount) internal view returns(uint256){
        uint256 tokenPrice = priceFeed.getPrice(address(_token));
        uint256 totalUSD = tokenPrice.mul(_amount).div(10**30); //as price feed uses 30 decimals
        uint256 decimals = _token.decimals();
        if(decimals > 18){
            totalUSD = totalUSD.div(10 ** (decimals - 18));
        }
        else if(decimals < 18){
            totalUSD = totalUSD.mul(10 ** (18 - decimals));
        }

        return totalUSD;
    }

    //Gets the swap fee between muchoTokens for a user, depending on the possesion of NFT
    function getSwapFee(address _user) public view returns(uint256){
        require(_user != address(0), "Not a valid user");
        uint256 swapFee = bpSwapMuchoTokensFee;
        IMuchoBadgeManager.Plan[] memory plans = badgeManager.activePlansForUser(_user);
        for(uint i = 0; i < plans.length; i = i.add(1)){
            uint256 id = plans[i].id;
            if(bpSwapMuchoTokensFeeForBadgeHolders[id].exists && bpSwapMuchoTokensFeeForBadgeHolders[id].fee < swapFee)
                swapFee = bpSwapMuchoTokensFeeForBadgeHolders[id].fee;
        }

        return swapFee;
    }


    //Returns the amount out (destination token) and to the owner (source token) for the swap
    function getDestinationAmountMuchoTokenExchange(uint8 _sourceVaultId, 
                                            uint8 _destVaultId,
                                            uint256 _amountSourceMToken,
                                            uint256 _ownerFeeAmount) 
                                                    internal view returns(uint256){
        require(_amountSourceMToken > 0, "Insufficent amount");

        uint256 sourcePrice = priceFeed.getPrice(address(vaultInfo[_sourceVaultId].depositToken)).div(10**12);
        uint256 destPrice = priceFeed.getPrice(address(vaultInfo[_destVaultId].depositToken)).div(10**12);
        uint256 decimalsDest = vaultInfo[_destVaultId].depositToken.decimals();
        uint256 decimalsSource = vaultInfo[_sourceVaultId].depositToken.decimals();

        //console.log("    SOL - prices", sourcePrice, destPrice);
        //console.log("    SOL - decimals", decimalsSource, decimalsDest);

        //Subtract owner fee
        if(_ownerFeeAmount > 0){
            _amountSourceMToken = _amountSourceMToken.sub(_ownerFeeAmount);
        }

        //console.log("    SOL - _amountSourceMToken after owner fee", _amountSourceMToken);

        uint256 amountTargetForUser = 0;
        {
            //console.log("    SOL - source totalStaked", vaultInfo[_sourceVaultId].totalStaked);
            //console.log("    SOL - source Price", sourcePrice);
            //console.log("    SOL - dest totalSupply", vaultInfo[_destVaultId].muchoToken.totalSupply());
            amountTargetForUser = _amountSourceMToken
                                        .mul(vaultInfo[_sourceVaultId].totalStaked)
                                        .mul(sourcePrice)
                                        .mul(vaultInfo[_destVaultId].muchoToken.totalSupply());
        }
        //decimals handling
        if(decimalsDest > decimalsSource){
            //console.log("    SOL - DecimalsBiggerDif|", decimalsDest - decimalsSource);
            amountTargetForUser = amountTargetForUser.mul(10**(decimalsDest - decimalsSource));
        }
        else if(decimalsDest < decimalsSource){
            //console.log("    SOL - DecimalsSmallerDif|", decimalsSource - decimalsDest);
            amountTargetForUser = amountTargetForUser.div(10**(decimalsSource - decimalsDest));
        }

        //console.log("    SOL - source totalSupply", vaultInfo[_sourceVaultId].muchoToken.totalSupply());
        //console.log("    SOL - dest totalStaked", vaultInfo[_sourceVaultId].muchoToken.totalSupply());
        amountTargetForUser = amountTargetForUser.div(vaultInfo[_sourceVaultId].muchoToken.totalSupply())
                                    .div(vaultInfo[_destVaultId].totalStaked)
                                    .div(destPrice);

        
        return amountTargetForUser;
    }
}
