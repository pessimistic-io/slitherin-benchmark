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
import {SafeMath} from "./SafeMath.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SushiRouterWrapper} from "./SushiRouterWrapper.sol";
import {DopexDpxSsovWrapper} from "./DopexDpxSsovWrapper.sol";

/// Interfaces
import {IDPXSSOVV2} from "./IDPXSSOVV2.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IJonesAsset} from "./IJonesAsset.sol";

/// @title Jones DPX V2 Vault
/// @author Jones DAO

contract JonesDPXVaultV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SushiRouterWrapper for IUniswapV2Router02;
    using DopexDpxSsovWrapper for IDPXSSOVV2;

    // jDPX Token
    IJonesAsset public jonesAssetToken;

    // DPX Token
    IERC20 public assetToken;

    // DPX SSOV contract
    IDPXSSOVV2 private SSOV;

    // Sushiswap router
    IUniswapV2Router02 private sushiRouter;

    // SushiRouterSellingtokens
    address[] private sellingTokens;

    // SushiRoutes
    address[][] private routes;

    // true if assets are under management
    // false if users can deposit and claim
    bool public MANAGEMENT_WINDOW_OPEN = true;

    // vault cap status
    bool public vaultCapSet = false;

    // wether we should charge fees
    bool public chargeFees = false;

    // vault cap value
    uint256 public vaultCap;

    // snapshot of the vault's DPX balance from previous epoch / before management starts
    uint256 public snapshotVaultBalance;

    // snapshot of jDPX total supply from previous epoch / before management starts
    uint256 public snapshotJonesAssetSupply;

    // DAO whitelist mapping
    mapping(address => uint256) public daoWhitelist;

    // The list of addresses the contract uses
    mapping(bytes32 => address) public addresses;

    /// @param _jonesAsset jDPX contract address.
    /// @param _asset DPX contract address.
    /// @param _SSOV SSOV contract address.
    /// @param _aumMultisigAddr AUM multisig address.
    /// @param _feeDistributor Address to which we send management and performance fees.
    /// @param _externalWhitelister Non multisig address which can add new addresses to the DAO whitelist.
    /// @param _snapshotVaultBalance Vault balance snapshot value.
    /// @param _snapshotJonesAssetSupply jDPX supply snapshot value.
    constructor(
        IJonesAsset _jonesAsset,
        IERC20 _asset,
        IDPXSSOVV2 _SSOV,
        address _aumMultisigAddr,
        address _feeDistributor,
        address _externalWhitelister,
        uint256 _snapshotVaultBalance,
        uint256 _snapshotJonesAssetSupply
    ) {
        require(_aumMultisigAddr != address(0), "VE1");
        require(_snapshotVaultBalance > 0, "VE2");
        require(_snapshotJonesAssetSupply > 0, "VE2");

        jonesAssetToken = _jonesAsset;
        assetToken = _asset;
        SSOV = _SSOV;
        snapshotVaultBalance = _snapshotVaultBalance;
        snapshotJonesAssetSupply = _snapshotJonesAssetSupply;

        // set addresses
        addresses["AUMMultisig"] = _aumMultisigAddr;
        addresses["FeeDistributor"] = _feeDistributor;
        addresses["Whitelistoor"] = _externalWhitelister;
        addresses["rDPX"] = 0x32Eb7902D4134bf98A28b963D26de779AF92A212;
        addresses["wETH"] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

        sushiRouter = IUniswapV2Router02(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );

        // Token spending approval for SushiSwap
        IERC20(getAddress("rDPX")).safeApprove(
            address(sushiRouter),
            type(uint256).max
        );

        // Token spending approval for SSOV
        assetToken.safeApprove(address(SSOV), type(uint256).max);

        sellingTokens = [getAddress("rDPX")];

        routes = [[getAddress("rDPX"), getAddress("wETH"), address(_asset)]];

        transferOwnership(_aumMultisigAddr);
    }

    // ============================== Depositing ==============================

    /// Mint jDPX by depositing DPX into the vault.
    /// @param _amount Amount of DPX to deposit.
    function depositAsset(uint256 _amount)
        public
        nonReentrant
        whenNotManagementWindow
    {
        require(_amount > 0, "VE2");

        if (vaultCapSet) {
            // if user is a whitelisted DAO
            if (isWhitelisted(msg.sender)) {
                require(_amount <= daoWhitelist[msg.sender], "VE2");

                // update whitelisted amount
                daoWhitelist[msg.sender] = daoWhitelist[msg.sender].sub(
                    _amount
                );

                emit WhitelistUpdate(msg.sender, daoWhitelist[msg.sender]);
            } else {
                require(
                    assetToken.balanceOf(address(this)).add(_amount) <=
                        vaultCap,
                    "VE3"
                );
            }
        }

        uint256 mintableJAsset = convertToJAsset(_amount);

        // deposit DPX into the vault
        assetToken.safeTransferFrom(msg.sender, address(this), _amount);

        // mint jDPX
        jonesAssetToken.mint(msg.sender, mintableJAsset);

        emit Deposited(msg.sender, mintableJAsset, _amount);
    }

    // ============================== Claiming ==============================

    /// Burn jDPX and redeem DPX from the vault.
    /// @dev Assumes both tokens have same decimal places.
    /// @param _amount Amount of jDPX to burn.
    function claimAsset(uint256 _amount)
        public
        nonReentrant
        whenNotManagementWindow
    {
        require(_amount > 0, "VE2");
        require(jonesAssetToken.balanceOf(msg.sender) >= _amount, "VE4");
        uint256 redeemableAsset = convertToAsset(_amount);

        // burn jDPX
        jonesAssetToken.burnFrom(msg.sender, _amount);

        // redeem DPX
        assetToken.transfer(msg.sender, redeemableAsset);

        emit Claimed(msg.sender, redeemableAsset, _amount);
    }

    // ============================== Setters ==============================

    /// Claims and deposits close, assets are under vault control.
    function openManagementWindow() public onlyOwner whenNotManagementWindow {
        _executeSnapshot();

        if (chargeFees) {
            // send management fee to fee distributor (2% annually)
            // 1 / 600 = 2 / (100 * 12)
            assetToken.safeTransfer(
                getAddress("FeeDistributor"),
                assetToken.balanceOf(address(this)).div(600)
            );
        }

        MANAGEMENT_WINDOW_OPEN = true;
        emit EpochStarted(
            block.timestamp,
            snapshotVaultBalance,
            snapshotJonesAssetSupply
        );
    }

    /// Initial setup of the vault.
    /// @dev run when vault should open for the first contract's epoch.
    /// @param _vaultCapSet True if vault cap is set.
    /// @param _vaultCap Vault cap (18 decimal).
    /// @param _snapshotVaultBalance Update vault balance (18 decimal).
    function initialRun(
        bool _vaultCapSet,
        uint256 _vaultCap,
        uint256 _snapshotVaultBalance
    ) public onlyOwner whenManagementWindow {
        // set vault cap if true
        if (_vaultCapSet) {
            require(_vaultCap > 0, "VE2");
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

    /// @notice Open vault for deposits and claims.
    /// @dev claims rewards from Dopex, sells DPX and rDPX rewards, sends performance fee to fee distributor.
    /// @param _vaultCapSet True if vault cap is set.
    /// @param _vaultCap Vault cap (18 decimal).
    /// @param _assetAmtFromrDpx DPX output amount from selling rDPX.
    function closeManagementWindow(
        bool _vaultCapSet,
        uint256 _vaultCap,
        uint256 _assetAmtFromrDpx
    ) public onlyOwner whenManagementWindow {
        // claim deposits and settle calls from SSOV
        SSOV.settleEpoch(address(this));

        // Sell rDPX for DPX
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _assetAmtFromrDpx;

        sushiRouter.sellTokens(amounts, sellingTokens, address(this), routes);

        uint256 balanceNow = assetToken.balanceOf(address(this));

        if ((balanceNow > snapshotVaultBalance) && chargeFees) {
            // send performance fee to fee distributor (20% on profit wrt benchmark)
            // 1 / 5 = 20 / 100
            assetToken.safeTransfer(
                getAddress("FeeDistributor"),
                balanceNow.sub(snapshotVaultBalance).div(5)
            );
        }

        // update snapshot
        _executeSnapshot();

        // set vault cap if true
        if (_vaultCapSet) {
            require(_vaultCap > 0, "VE2");
            vaultCap = _vaultCap;
            vaultCapSet = true;
        }

        MANAGEMENT_WINDOW_OPEN = false;
        emit EpochEnded(
            block.timestamp,
            snapshotVaultBalance,
            snapshotJonesAssetSupply
        );
    }

    /// Update SSOV contract address in case it changes.
    /// @dev This function is called by the AUM multisig.
    function updateSSOVAddress(IDPXSSOVV2 _newSSOV) public onlyOwner {
        assetToken.safeApprove(address(SSOV), 0); // revoke old
        SSOV = _newSSOV;
        assetToken.safeApprove(address(SSOV), type(uint256).max); // approve new
    }

    /// Update vault value snapshot.
    function _executeSnapshot() private {
        snapshotJonesAssetSupply = jonesAssetToken.totalSupply();
        snapshotVaultBalance = assetToken.balanceOf(address(this));

        emit Snapshot(
            block.timestamp,
            snapshotVaultBalance,
            snapshotJonesAssetSupply
        );
    }

    // ============================== AUM multisig functions ==============================

    /// Migrate vault to new vault contract.
    /// @dev acts as emergency withdrawal if needed.
    /// @param _to New vault contract address.
    /// @param _tokens Addresses of tokens to be migrated.
    function migrateVault(address _to, address[] memory _tokens)
        public
        onlyOwner
        whenManagementWindow
    {
        // migrate other ERC20 Tokens
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 tkn = IERC20(_tokens[i]);
            uint256 assetBalance = tkn.balanceOf(address(this));
            if (assetBalance > 0) {
                tkn.transfer(_to, assetBalance);
            }
        }

        // migrate ETH balance
        uint256 balanceGwei = address(this).balance;
        if (balanceGwei > 0) {
            payable(_to).transfer(balanceGwei);
        }
    }

    /// Update whether we should be charging fees.
    function setChargeFees(bool _status) public onlyOwner {
        chargeFees = _status;
    }

    // ============================== Dopex interaction ==============================

    /**
     * Deposits funds to SSOV at desired strike price.
     * @param _strikeIndex Strike price index.
     * @param _amount Amount of DPX to deposit.
     * @return Whether deposit was successful.
     */
    function depositSSOV(uint256 _strikeIndex, uint256 _amount)
        public
        onlyOwner
        whenManagementWindow
        returns (bool)
    {
        return SSOV.depositSSOV(_strikeIndex, _amount, address(this));
    }

    /**
     * Deposits funds to SSOV at multiple desired strike prices.
     * @param _strikeIndices Strike price indices.
     * @param _amounts Amounts of DPX to deposit.
     * @return Whether deposits went through successfully.
     */
    function depositSSOVMultiple(
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts
    ) public onlyOwner whenManagementWindow returns (bool) {
        return
            SSOV.depositSSOVMultiple(_strikeIndices, _amounts, address(this));
    }

    /**
     * Buys calls from Dopex SSOV.
     * @param _strikeIndex Strike index for current epoch.
     * @param _amount Amount of calls to purchase.
     * @return Whether call purchase went through successfully.
     */
    function purchaseCall(uint256 _strikeIndex, uint256 _amount)
        public
        onlyOwner
        whenManagementWindow
        returns (bool)
    {
        return SSOV.purchaseCall(_strikeIndex, _amount, address(this));
    }

    // ============================== DAO Whitelist ==============================

    /// Adds a new DAO to the whitelist.
    /// @param _addr address to be added to the whitelist.
    /// @param _amount allowed amount for this address.
    function addToWhitelist(address _addr, uint256 _amount)
        public
        onlyWhitelistoors
    {
        require(!isWhitelisted(_addr), "VE5");
        daoWhitelist[_addr] = _amount;
        emit WhitelistUpdate(_addr, _amount);
    }

    /// Check if address is whitelisted.
    /// @param _addr address to be checked.
    /// @return Whether address is whitelisted.
    function isWhitelisted(address _addr) public view returns (bool) {
        return daoWhitelist[_addr] > 0;
    }

    /// Removes an address from the whitelist.
    /// @param _addr address to be removed.
    function removeFromWhitelist(address _addr) public onlyWhitelistoors {
        require(isWhitelisted(_addr), "VE6");
        daoWhitelist[_addr] = 0;
        emit WhitelistUpdate(_addr, 0);
    }

    // ============================== Views ==============================

    /// Calculates claimable DPX for a given user.
    /// @param _user user address.
    /// @return claimable DPX.
    function claimableAsset(address _user) public view returns (uint256) {
        uint256 usrBalance = jonesAssetToken.balanceOf(_user);
        if (usrBalance > 0) {
            return convertToAsset(usrBalance);
        }
        return 0;
    }

    /// Calculates claimable DPX amount for a given amount of jDPX.
    /// @param _jAssetAmount Amount of jDPX.
    /// @return claimable DPX amount.
    function convertToAsset(uint256 _jAssetAmount)
        public
        view
        returns (uint256)
    {
        return
            _jAssetAmount.mul(snapshotVaultBalance).div(
                snapshotJonesAssetSupply
            );
    }

    /// Calculates mintable jDPX amount for a given amount of DPX.
    /// @param _assetAmount Amount of DPX.
    /// @return mintable jDPX amount.
    function convertToJAsset(uint256 _assetAmount)
        public
        view
        returns (uint256)
    {
        return
            _assetAmount.mul(snapshotJonesAssetSupply).div(
                snapshotVaultBalance
            );
    }

    /// Gets the address of a set contract
    /// @param _name Name of the contract
    /// @return The address of the contract
    function getAddress(bytes32 _name) public view returns (address) {
        return addresses[_name];
    }

    // ============================== Modifiers ==============================

    /// When both deposits and claiming are closed, vault can manage DPX.
    modifier whenManagementWindow() {
        require(MANAGEMENT_WINDOW_OPEN, "VE7");
        _;
    }

    /// When management window is closed, deposits and claiming are open.
    modifier whenNotManagementWindow() {
        require(!MANAGEMENT_WINDOW_OPEN, "VE8");
        _;
    }

    /// When message sender is either the multisig or the whitelist manager
    modifier onlyWhitelistoors() {
        require(
            msg.sender == owner() || msg.sender == getAddress("Whitelistoor"),
            "VE9"
        );
        _;
    }

    // ============================== Events ==============================

    /// emitted on user deposit
    /// @param _from depositor address (indexed)
    /// @param _assetAmount DPX deposit amount
    /// @param _jonesAssetAmount jDPX mint amount
    event Deposited(
        address indexed _from,
        uint256 _assetAmount,
        uint256 _jonesAssetAmount
    );

    /// emitted on user claim
    /// @param _from claimer address (indexed)
    /// @param _assetAmount DPX claim amount
    /// @param _jonesAssetAmount jDPX burn amount
    event Claimed(
        address indexed _from,
        uint256 _assetAmount,
        uint256 _jonesAssetAmount
    );

    /// emitted when vault balance snapshot is taken
    /// @param _timestamp snapshot timestamp (indexed)
    /// @param _vaultBalance vault balance value
    /// @param _jonesAssetSupply jDPX total supply value
    event Snapshot(
        uint256 indexed _timestamp,
        uint256 _vaultBalance,
        uint256 _jonesAssetSupply
    );

    /// emitted when asset management window is opened
    /// @param _timestamp snapshot timestamp (indexed)
    /// @param _assetAmount new vault balance value
    /// @param _jonesAssetSupply jDPX total supply at this time
    event EpochStarted(
        uint256 indexed _timestamp,
        uint256 _assetAmount,
        uint256 _jonesAssetSupply
    );

    /// emitted when claim and deposit windows are open
    /// @param _timestamp snapshot timestamp (indexed)
    /// @param _assetAmount new vault balance value
    /// @param _jonesAssetSupply jDPX total supply at this time
    event EpochEnded(
        uint256 indexed _timestamp,
        uint256 _assetAmount,
        uint256 _jonesAssetSupply
    );

    /// emitted when whitelist is updated
    /// @param _address whitelisted address (indexed)
    /// @param _amount whitelisted new amount
    event WhitelistUpdate(address indexed _address, uint256 _amount);
}

// ERROR MAPPING:
// {
//   "VE1": "Vault: Address cannot be a zero address",
//   "VE2": "Vault: Invalid amount",
//   "VE3": "Vault: Amount exceeds vault cap",
//   "VE4": "Vault: Insufficient balance",
//   "VE5": "Vault: Already whitelisted",
//   "VE6": "Vault: Address not in whitelist",
//   "VE7": "Vault: Management window is not open",
//   "VE8": "Vault: Management window is  open",
//   "VE9": "Vault: User does not have whitelisting permissions",
// }

