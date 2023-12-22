// SPDX-License-Identifier: GPL-3.0
/*                            ******@@@@@@@@@**@*                               
                        ***@@@@@@@@@@@@@@@@@@@@@@**                             
                     *@@@@@@**@@@@@@@@@@@@@@@@@*@@@*                            
                  *@@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@*@**                          
                 *@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@*                         
                **@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@**                       
                **@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@@@@@*                      
                **@@@@@@@@@@@@@@@@*************************                    
                **@@@@@@@@***********************************                   
                 *@@@***********************&@@@@@@@@@@@@@@@****,    ******@@@@*
           *********************@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@************* 
      ***@@@@@@@@@@@@@@@*****@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@****@@*********      
   **@@@@@**********************@@@@*****************#@@@@**********            
  *@@******************************************************                     
 *@************************************                                         
 @*******************************                                               
 *@*************************                                                    
   ********************* 
   
    /$$$$$                                               /$$$$$$$   /$$$$$$   /$$$$$$ 
   |__  $$                                              | $$__  $$ /$$__  $$ /$$__  $$
      | $$  /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$$      | $$  \ $$| $$  \ $$| $$  \ $$
      | $$ /$$__  $$| $$__  $$ /$$__  $$ /$$_____/      | $$  | $$| $$$$$$$$| $$  | $$
 /$$  | $$| $$  \ $$| $$  \ $$| $$$$$$$$|  $$$$$$       | $$  | $$| $$__  $$| $$  | $$
| $$  | $$| $$  | $$| $$  | $$| $$_____/ \____  $$      | $$  | $$| $$  | $$| $$  | $$
|  $$$$$$/|  $$$$$$/| $$  | $$|  $$$$$$$ /$$$$$$$/      | $$$$$$$/| $$  | $$|  $$$$$$/
 \______/  \______/ |__/  |__/ \_______/|_______/       |_______/ |__/  |__/ \______/                                      
*/

pragma solidity ^0.8.2;

/// Libraries
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SushiRouterWrapper} from "./SushiRouterWrapper.sol";
import {DopexArbEthSsovWrapper} from "./DopexArbEthSsovWrapper.sol";
import {Curve2PoolSsovPutWrapper} from "./Curve2PoolSsovPutWrapper.sol";
import {Curve2PoolWrapper} from "./Curve2PoolWrapper.sol";

/// Interfaces
import {IArbEthSSOVV2} from "./IArbEthSSOVV2.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IwETH} from "./IwETH.sol";
import {IJonesAsset} from "./IJonesAsset.sol";
import {ICurve2PoolSsovPut} from "./ICurve2PoolSsovPut.sol";
import {IStableSwap} from "./IStableSwap.sol";

/// @title Jones ETH V2 Vault
/// @author Jones DAO

contract JonesArbETHVaultV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SushiRouterWrapper for IUniswapV2Router02;
    using DopexArbEthSsovWrapper for IArbEthSSOVV2;
    using Curve2PoolSsovPutWrapper for ICurve2PoolSsovPut;
    using Curve2PoolWrapper for IStableSwap;

    // jETH contract
    IJonesAsset public jonesAssetToken;

    // ETH SSOV contract
    IArbEthSSOVV2 private SSOV;

    // ETH SSOV-P contract
    ICurve2PoolSsovPut private SSOVP;

    // Sushiswap router
    IUniswapV2Router02 private sushiRouter;

    // Curve stable swap
    IStableSwap private stableSwap;

    // SushiRouterSellingtokens
    address[] private sellingTokens;

    // SushiRoutes
    address[][] private routes;

    // true if assets are under management
    // false if users can deposit and claim
    bool public MANAGEMENT_WINDOW_OPEN = true;

    // If epoch as already been settled
    bool public SETTLED_EPOCH = false;

    // vault cap status
    bool public vaultCapSet = false;

    // whether we should charge fees
    bool public chargeFees = false;

    // vault cap value
    uint256 public vaultCap;

    // snapshot of the vault's ETH balance from previous epoch / before management starts
    uint256 public snapshotVaultBalance;

    // snapshot of jETH total supply from previous epoch / before management starts
    uint256 public snapshotJonesAssetSupply;

    // DAO whitelist mapping
    mapping(address => uint256) public daoWhitelist;

    // Governance address
    address private AUMMultisig;

    // Fee distributor contract address
    address private FeeDistributor;

    // Whitelistoor address
    address private Whitelistoor;

    // DPX Token address
    address private DPX;

    // rDPX Token address
    address private rDPX;

    // wETH Token address
    address private wETH;

    // USDC Token address
    address private USDC;

    /*
     * @param _jonesAsset jETH contract address.
     * @param _SSOV SSOV contract address.
     * @param _SSOVP SSOV-P contract address.
     * @param _aumMultisigAddr AUM multisig address.
     * @param _feeDistributor Address to which we send management and performance fees.
     * @param _externalWhitelister Non multisig address which can add new addresses to the DAO whitelist.
     * @param _snapshotVaultBalance Vault balance snapshot value.
     * @param _snapshotJonesAssetSupply jETH supply snapshot value.
     */
    constructor(
        IJonesAsset _jonesAsset,
        IArbEthSSOVV2 _SSOV,
        ICurve2PoolSsovPut _SSOVP,
        address _aumMultisigAddr,
        address _feeDistributor,
        address _externalWhitelister,
        uint256 _snapshotVaultBalance,
        uint256 _snapshotJonesAssetSupply
    ) {
        if (_aumMultisigAddr == address(0)) revert VE1();
        if (_snapshotVaultBalance == 0) revert VE2();
        if (_snapshotJonesAssetSupply == 0) revert VE2();

        // set snapshot values
        snapshotVaultBalance = _snapshotVaultBalance;
        snapshotJonesAssetSupply = _snapshotJonesAssetSupply;

        // set addresses
        jonesAssetToken = _jonesAsset;
        SSOV = _SSOV;
        SSOVP = _SSOVP;
        AUMMultisig = _aumMultisigAddr;
        FeeDistributor = _feeDistributor;
        Whitelistoor = _externalWhitelister;
        DPX = 0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55;
        rDPX = 0x32Eb7902D4134bf98A28b963D26de779AF92A212;
        wETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

        // SushiSwap router
        sushiRouter = IUniswapV2Router02(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );

        // 2CRV
        stableSwap = IStableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

        // Token spending approval for Curve 2pool
        IERC20(USDC).safeApprove(address(stableSwap), type(uint256).max);

        // Token spending approvals for SushiSwap
        IERC20(DPX).safeApprove(address(sushiRouter), type(uint256).max);
        IERC20(rDPX).safeApprove(address(sushiRouter), type(uint256).max);
        IERC20(USDC).safeApprove(address(sushiRouter), type(uint256).max);

        // Token spending approval for SSOV-P
        stableSwap.approve(address(SSOVP), type(uint256).max);

        sellingTokens = [DPX, rDPX, USDC];

        // 0: DPX -> wETH | 1: rDPX -> wETH | 2: USDC -> wETH
        routes = [[DPX, wETH], [rDPX, wETH], [USDC, wETH]];

        // Give governance contract ownership
        transferOwnership(_aumMultisigAddr);
    }

    // ============================== Depositing ==============================

    /**
     * Mint jETH by depositing ETH into the vault.
     * @param _amount Amount of ETH to deposit.
     */
    function depositAsset(uint256 _amount) public payable nonReentrant {
        _whenNotManagementWindow();
        if (msg.value < _amount || _amount == 0) revert VE2();

        if (vaultCapSet) {
            // if user is a whitelisted DAO
            if (isWhitelisted(msg.sender)) {
                if (_amount > daoWhitelist[msg.sender]) revert VE2();

                // update whitelisted amount
                daoWhitelist[msg.sender] = daoWhitelist[msg.sender] - _amount;

                emit WhitelistUpdate(msg.sender, daoWhitelist[msg.sender]);
            } else {
                if (address(this).balance + msg.value > vaultCap) revert VE3();
            }
        }

        uint256 mintableJAsset = convertToJAsset(_amount);

        // mint jETH
        jonesAssetToken.mint(msg.sender, mintableJAsset);

        // refund excess ETH sent by msg.sender
        if (msg.value > _amount) {
            payable(msg.sender).transfer(msg.value - _amount);
        }

        emit Deposited(msg.sender, mintableJAsset, _amount);
    }

    /**
     * Deposit fallback function - DO NOT USE THIS TO DEPOSIT YOUR ETH.
     */
    receive() external payable {}

    // ============================== Claiming ==============================

    /**
     * Burn jETH and redeem ETH from the vault.
     * @dev Assumes both tokens have same decimal places.
     * @param _amount Amount of jETH to burn.
     */
    function claimAsset(uint256 _amount) public nonReentrant {
        _whenNotManagementWindow();
        if (_amount == 0) revert VE2();
        if (jonesAssetToken.balanceOf(msg.sender) < _amount) revert VE4();
        uint256 redeemableAsset = convertToAsset(_amount);

        // burn jETH
        jonesAssetToken.burnFrom(msg.sender, _amount);

        // redeem ETH
        payable(msg.sender).transfer(redeemableAsset);

        emit Claimed(msg.sender, redeemableAsset, _amount);
    }

    // ============================== Setters ==============================

    /**
     * Claims and deposits close, assets are under vault control.
     */
    function openManagementWindow() public onlyOwner {
        _whenNotManagementWindow();
        _executeSnapshot();

        MANAGEMENT_WINDOW_OPEN = true;
        emit EpochStarted(
            block.timestamp,
            snapshotVaultBalance,
            snapshotJonesAssetSupply
        );
    }

    /**
     * Initial setup of the vault.
     * @dev run when vault should open for the first contract's epoch.
     * @param _vaultCapSet True if vault cap is set.
     * @param _vaultCap Vault cap (18 decimal).
     * @param _snapshotVaultBalance Update vault balance (18 decimal).
     */
    function initialRun(
        bool _vaultCapSet,
        uint256 _vaultCap,
        uint256 _snapshotVaultBalance
    ) public onlyOwner {
        _whenManagementWindow();
        // set vault cap if true
        if (_vaultCapSet) {
            if (_vaultCap == 0) revert VE2();
            vaultCap = _vaultCap;
            vaultCapSet = true;
        }

        snapshotVaultBalance = _snapshotVaultBalance;

        MANAGEMENT_WINDOW_OPEN = false;
        emit EpochEnded(
            block.timestamp,
            snapshotVaultBalance,
            snapshotJonesAssetSupply
        );
    }

    /**
     * @notice Settles the SSOV and SSOV-P epochs
     * @param _usdcAmount The minumum amount of USDC to receive.
     * @param _ssovEpoch The SSOV epoch to settle.
     * @param _ssovStrikes The SSOV strike indexes to settle.
     * @param _ssovpEpoch The SSOV-P epoch to settle.
     * @param _ssovpStrikes The SSOV-P strike indexes to settle.
     */
    function settleEpoch(
        uint256 _usdcAmount,
        uint256 _ssovEpoch,
        uint256[] memory _ssovStrikes,
        uint256 _ssovpEpoch,
        uint256[] memory _ssovpStrikes
    ) public onlyOwner {
        _whenManagementWindow();

        // claim deposits and settle calls/puts from SSOV/SSOV-P
        SSOV.settleEpoch(address(this), _ssovEpoch, _ssovStrikes);
        SSOVP.settleEpoch(address(this), _ssovpEpoch, _ssovpStrikes);

        // Sell 2CRV for USDC
        uint256 _2crvBalance = stableSwap.balanceOf(address(this));
        if (_2crvBalance > 0)
            stableSwap.swap2CrvForStable(USDC, _2crvBalance, _usdcAmount);

        SETTLED_EPOCH = true;
    }

    /**
     * Used in case of any emergency to withdraw from SSOV's
     * @param _ssovcStrikeIndexes SSOV-C indexes to withdraw (empty if not needed)
     * @param _ssovcEpoch SSOV-C epoch to withdraw
     * @param _ssovpStrikeIndexes SSOV-P indexes to withdraw (empty if not needed)
     * @param _ssovpEpoch SSOV-P epoch to withdraw
     */
    function emergencyWithdrawSSOV(
        uint256[] memory _ssovcStrikeIndexes,
        uint256 _ssovcEpoch,
        uint256[] memory _ssovpStrikeIndexes,
        uint256 _ssovpEpoch
    ) public onlyOwner {
        _whenManagementWindow();
        SSOV.withdrawEpoch(_ssovcStrikeIndexes, _ssovcEpoch);
        SSOVP.withdrawEpoch(_ssovpStrikeIndexes, _ssovpEpoch);
    }

    /**
     * @notice Open vault for deposits and claims.
     * @dev claims rewards from Dopex, sells DPX and rDPX rewards, unwraps all wETH, sends performance fee to fee distributor.
     * @param _vaultCapSet True if vault cap is set.
     * @param _vaultCap Vault cap (18 decimal).
     * @param _assetAmtFromDpx wETH output amount from selling DPX.
     * @param _assetAmtFromrDpx wETH output amount from selling rDPX.
     * @param _assetAmtFromUsdc wETH output amount from selling USDC.
     */
    function closeManagementWindow(
        bool _vaultCapSet,
        uint256 _vaultCap,
        uint256 _assetAmtFromDpx,
        uint256 _assetAmtFromrDpx,
        uint256 _assetAmtFromUsdc
    ) public onlyOwner {
        _whenManagementWindow();
        if (!SETTLED_EPOCH) revert VE8();

        // Sell DPX, rDPX and USDC for ETH
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _assetAmtFromDpx;
        amounts[1] = _assetAmtFromrDpx;
        amounts[2] = _assetAmtFromUsdc;

        sushiRouter.sellTokensForEth(
            amounts,
            sellingTokens,
            address(this),
            routes
        );

        // Unwrap wETH if any
        if (IwETH(wETH).balanceOf(address(this)) > 0)
            IwETH(wETH).withdraw(IwETH(wETH).balanceOf(address(this)));

        // Charge fees if needed
        _chargeFees();

        // update snapshot
        _executeSnapshot();

        // set vault cap if true
        if (_vaultCapSet) {
            if (_vaultCap == 0) revert VE2();
            vaultCap = _vaultCap;
            vaultCapSet = true;
        }

        MANAGEMENT_WINDOW_OPEN = false;
        SETTLED_EPOCH = false;
        emit EpochEnded(
            block.timestamp,
            snapshotVaultBalance,
            snapshotJonesAssetSupply
        );
    }

    /**
     * Update SSOV contract address in case it changes.
     * @dev This function is called by the AUM multisig.
     */
    function updateSSOVAddress(IArbEthSSOVV2 _newSSOV) public onlyOwner {
        SSOV = _newSSOV;
    }

    /**
     * Update SSOV-P contract address in case it changes.
     * @dev This function is called by the AUM multisig.
     */
    function updateSSOVPAddress(ICurve2PoolSsovPut _newSSOVP) public onlyOwner {
        SSOVP = _newSSOVP;
    }

    /**
     * Update vault value snapshot.
     */
    function _executeSnapshot() private {
        snapshotJonesAssetSupply = jonesAssetToken.totalSupply();
        snapshotVaultBalance = address(this).balance;

        emit Snapshot(
            block.timestamp,
            snapshotVaultBalance,
            snapshotJonesAssetSupply
        );
    }

    /**
     * Charge performance and management fees if needed
     */
    function _chargeFees() private {
        if (chargeFees) {
            uint256 balanceNow = address(this).balance;
            if (balanceNow > snapshotVaultBalance) {
                // send performance fee to fee distributor (20% on profit wrt benchmark)\
                // 1 / 5 = 20 / 100
                payable(FeeDistributor).transfer(
                    (balanceNow - snapshotVaultBalance) / 5
                );
            }
            // send management fee to fee distributor (2% annually)
            // 1 / 600 = 2 / (100 * 12)
            payable(FeeDistributor).transfer(snapshotVaultBalance / 600);
        }
    }

    // ============================== AUM multisig functions ==============================

    /**
     * Migrate vault to new vault contract.
     * @dev acts as emergency withdrawal if needed.
     * @param _to New vault contract address.
     * @param _tokens Addresses of tokens to be migrated.
     */
    function migrateVault(address _to, address[] memory _tokens)
        public
        onlyOwner
    {
        // migrate other ERC20 Tokens
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 tkn = IERC20(_tokens[i]);
            uint256 assetBalance = tkn.balanceOf(address(this));
            if (assetBalance > 0) {
                tkn.safeTransfer(_to, assetBalance);
            }
        }

        // migrate ETH balance
        uint256 balanceGwei = address(this).balance;
        if (balanceGwei > 0) {
            payable(_to).transfer(balanceGwei);
        }
    }

    /**
     * Update whether we should be charging fees.
     */
    function setChargeFees(bool _status) public onlyOwner {
        chargeFees = _status;
    }

    // ============================== Dopex interaction ==============================

    /**
     * Deposits funds to SSOV at desired strike price.
     * @param _strikeIndex Strike price index.
     * @param _amount Amount of ETH to deposit.
     * @return Whether deposit was successful.
     */
    function depositSSOV(uint256 _strikeIndex, uint256 _amount)
        public
        onlyOwner
        returns (bool)
    {
        _whenManagementWindow();
        return SSOV.depositSSOV(_strikeIndex, _amount, address(this));
    }

    /**
     * Deposits funds to SSOV at multiple desired strike prices.
     * @param _strikeIndices Strike price indices.
     * @param _amounts Amounts of ETH to deposit.
     * @return Whether deposits went through successfully.
     */
    function depositSSOVMultiple(
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts
    ) public onlyOwner returns (bool) {
        _whenManagementWindow();
        return
            SSOV.depositSSOVMultiple(_strikeIndices, _amounts, address(this));
    }

    /**
     * Buys calls from Dopex SSOV.
     * @param _strikeIndex Strike index for current epoch.
     * @param _amount Amount of calls to purchase.
     * @param _price Amount of ETH we are willing to pay for these calls.
     * @return Whether call purchase went through successfully.
     */
    function purchaseCall(
        uint256 _strikeIndex,
        uint256 _amount,
        uint256 _price
    ) public onlyOwner returns (bool) {
        _whenManagementWindow();
        return SSOV.purchaseCall(_strikeIndex, _amount, _price, address(this));
    }

    /**
     * Deposits funds to SSOV-P at desired strike price.
     * @param _strikeIndex Strike price index.
     * @param _amount Amount of 2CRV to deposit.
     * @return Whether deposit was successful.
     */
    function depositSSOVP(uint256 _strikeIndex, uint256 _amount)
        public
        onlyOwner
        returns (bool)
    {
        _whenManagementWindow();
        return SSOVP.depositSSOVP(_strikeIndex, _amount, address(this));
    }

    /**
     * Deposits funds to SSOV at multiple desired strike prices.
     * @param _strikeIndices Strike price indices.
     * @param _amounts Amounts of DPX to deposit.
     * @return Whether deposits went through successfully.
     */
    function depositSSOVPMultiple(
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts
    ) public onlyOwner returns (bool) {
        _whenManagementWindow();
        return
            SSOVP.depositSSOVPMultiple(_strikeIndices, _amounts, address(this));
    }

    /**
     * Buys puts from Dopex SSOV-P.
     * @param _strikeIndex Strike index for current epoch.
     * @param _amount Amount of puts to purchase.
     * @return Whether put purchase went through sucessfully.
     */
    function purchasePut(uint256 _strikeIndex, uint256 _amount)
        public
        onlyOwner
        returns (bool)
    {
        _whenManagementWindow();
        return SSOVP.purchasePut(_strikeIndex, _amount, address(this));
    }

    // ============================== wETH interaction ==============================

    /**
     * Wraps a given amount of ETH.
     * @param _amount Amount of ETH to be wrapped.
     * @return Whether wrapping was successful.
     */
    function wrapETH(uint256 _amount) public onlyOwner returns (bool) {
        _whenManagementWindow();
        IwETH(wETH).deposit{value: _amount}();
        return true;
    }

    /**
     * Unwraps a given amount of wETH.
     * @param _amount Amount of wETH to be unwrapped.
     * @return Whether unwrapping was successful.
     */
    function unwrapwETH(uint256 _amount) public onlyOwner returns (bool) {
        _whenManagementWindow();
        IwETH(wETH).withdraw(_amount);
        return true;
    }

    // ============================== 2CRV Interactions ==============================

    /**
     * @notice Sells the base asset for 2CRV
     * @param _baseAmount The amount of base asset to sell
     * @param _stableToken The address of the stable token that will be used as intermediary to get 2CRV
     * @param _minStableAmount The minimum amount of `_stableToken` to get when swapping base
     * @param _min2CrvAmount The minimum amount of 2CRV to receive
     * @return The amount of 2CRV tokens
     */
    function sellBaseFor2Crv(
        uint256 _baseAmount,
        address _stableToken,
        uint256 _minStableAmount,
        uint256 _min2CrvAmount
    ) public onlyOwner returns (uint256) {
        _whenManagementWindow();
        return
            stableSwap.swapNativeFor2Crv(
                _baseAmount,
                _stableToken,
                _minStableAmount,
                _min2CrvAmount,
                address(this)
            );
    }

    /**
     * @notice Sells 2CRV for the base asset
     * @param _amount The amount of 2CRV to sell
     * @param _stableToken The address of the stable token to receive when removing 2CRV lp
     * @param _minStableAmount The minimum amount of `_stableToken` to get when swapping 2CRV
     * @param _minAssetAmount The minimum amount of base asset to receive
     * @return The amount of base asset
     */
    function sell2CrvForBase(
        uint256 _amount,
        address _stableToken,
        uint256 _minStableAmount,
        uint256 _minAssetAmount
    ) public onlyOwner returns (uint256) {
        _whenManagementWindow();
        return
            stableSwap.swap2CrvForNative(
                _amount,
                _stableToken,
                _minStableAmount,
                _minAssetAmount,
                address(this)
            );
    }

    // ============================== DAO Whitelist ==============================

    /**
     * Updates whitelisted amount for a DAO. (Set to 0 to remove)
     * @param _addr whitelisted address.
     * @param _amount whitelisted deposit amount for this DAO.
     */
    function updateWhitelistedAmount(address _addr, uint256 _amount) public {
        _onlyWhitelistoors();
        daoWhitelist[_addr] = _amount;
        emit WhitelistUpdate(_addr, _amount);
    }

    /**
     * Check if address is whitelisted.
     * @param _addr address to be checked.
     * @return Whether address is whitelisted.
     */
    function isWhitelisted(address _addr) public view returns (bool) {
        return daoWhitelist[_addr] > 0;
    }

    // ============================== Views ==============================

    /**
     * Calculates claimable ETH for a given user.
     * @param _user user address.
     * @return claimable ETH.
     */
    function claimableAsset(address _user) public view returns (uint256) {
        uint256 usrBalance = jonesAssetToken.balanceOf(_user);
        if (usrBalance > 0) {
            return convertToAsset(usrBalance);
        }
        return 0;
    }

    /**
     * Calculates claimable ETH amount for a given amount of jETH.
     * @param _jAssetAmount Amount of jETH.
     * @return claimable ETH amount.
     */
    function convertToAsset(uint256 _jAssetAmount)
        public
        view
        returns (uint256)
    {
        return
            (_jAssetAmount * snapshotVaultBalance) / snapshotJonesAssetSupply;
    }

    /**
     * Calculates mintable jETH amount for a given amount of ETH.
     * @param _assetAmount Amount of ETH.
     * @return mintable jETH amount.
     */
    function convertToJAsset(uint256 _assetAmount)
        public
        view
        returns (uint256)
    {
        return (_assetAmount * snapshotJonesAssetSupply) / snapshotVaultBalance;
    }

    // ============================== Helpers ==============================

    /**
     * When both deposits and claiming are closed, vault can manage ETH.
     */
    function _whenManagementWindow() internal view {
        if (!MANAGEMENT_WINDOW_OPEN) revert VE5();
    }

    /**
     * When management window is closed, deposits and claiming are open.
     */
    function _whenNotManagementWindow() internal view {
        if (MANAGEMENT_WINDOW_OPEN) revert VE6();
    }

    /**
     * When message sender is either the multisig or the whitelist manager
     */
    function _onlyWhitelistoors() internal view {
        if (!(msg.sender == owner() || msg.sender == Whitelistoor))
            revert VE7();
    }

    // ============================== Events ==============================

    /**
     * emitted on user deposit
     * @param _from depositor address (indexed)
     * @param _assetAmount ETH deposit amount
     * @param _jonesAssetAmount jETH mint amount
     */
    event Deposited(
        address indexed _from,
        uint256 _assetAmount,
        uint256 _jonesAssetAmount
    );

    /**  emitted on user claim
     * @param _from claimer address (indexed)
     * @param _assetAmount ETH claim amount
     * @param _jonesAssetAmount jETH burn amount
     */
    event Claimed(
        address indexed _from,
        uint256 _assetAmount,
        uint256 _jonesAssetAmount
    );

    /**
     * emitted when vault balance snapshot is taken
     * @param _timestamp snapshot timestamp (indexed)
     * @param _vaultBalance vault balance value
     * @param _jonesAssetSupply jETH total supply value
     */
    event Snapshot(
        uint256 indexed _timestamp,
        uint256 _vaultBalance,
        uint256 _jonesAssetSupply
    );

    /**
     * emitted when asset management window is opened
     * @param _timestamp snapshot timestamp (indexed)
     * @param _assetAmount new vault balance value
     * @param _jonesAssetSupply jETH total supply at this time
     */
    event EpochStarted(
        uint256 indexed _timestamp,
        uint256 _assetAmount,
        uint256 _jonesAssetSupply
    );

    /** emitted when claim and deposit windows are open
     * @param _timestamp snapshot timestamp (indexed)
     * @param _assetAmount new vault balance value
     * @param _jonesAssetSupply jETH total supply at this time
     */
    event EpochEnded(
        uint256 indexed _timestamp,
        uint256 _assetAmount,
        uint256 _jonesAssetSupply
    );

    /**
     * emitted when whitelist is updated
     * @param _address whitelisted address (indexed)
     * @param _amount whitelisted new amount
     */
    event WhitelistUpdate(address indexed _address, uint256 _amount);

    /**
     * Errors
     */
    error VE1();
    error VE2();
    error VE3();
    error VE4();
    error VE5();
    error VE6();
    error VE7();
    error VE8();
}

/**
 * ERROR MAPPING:
 * {
 *   "VE1": "Vault: Address cannot be a zero address",
 *   "VE2": "Vault: Invalid amount",
 *   "VE3": "Vault: Amount exceeds vault cap",
 *   "VE4": "Vault: Insufficient balance",
 *   "VE5": "Vault: Management window is not open",
 *   "VE6": "Vault: Management window is  open",
 *   "VE7": "Vault: User does not have whitelisting permissions",
 *   "VE8": "Vault: Cannot close management window if settle is not done",
 * }
 */

