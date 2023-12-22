//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.16;

// ====================================================================
// ======================= BaseSweep.sol ==============================
// ====================================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ITransferApprover.sol";

contract BaseSweep is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // Addresses
    address public timelock_address;
    address public multisig_address;
    address public transfer_approver_address;
    address public DEFAULT_ADMIN_ADDRESS;

    ITransferApprover private transferApprover;

    // Possible admin types
    enum AdminType {
        Wallet,
        Multisig,
        Governance
    }

    AdminType public current_admin_type;

    // Structs
    struct Minter {
        bool is_listed;
        uint256 max_mint_amount;
        uint256 minted_amount;
        bool is_mint_enabled;
    }

    // Minters
    mapping(address => Minter) public minters;

    // Events
    event TokenBurned(address indexed from, uint256 amount);
    event TokenMinted(address indexed from, address indexed to, uint256 amount);
    event MinterAdded(address minter_address, Minter new_minter);
    event MinterUpdated(address minter_address, Minter minter);
    event MinterRemoved(address minter_address);
    event TimelockSet(address new_timelock);
    event ApproverSet(address new_approver);
    event MultisigSet(address new_multisig);
    event AdminTypeSet(AdminType new_admin_type);

    /* ========== CONSTRUCTOR ========== */

    function __Sweep_init(
        address _timelock_address,
        address _multisig_address,
        address _transfer_approver_address,
        string memory _name,
        string memory _symbol
    ) public onlyInitializing {
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        __Pausable_init();

        DEFAULT_ADMIN_ADDRESS = _msgSender();
        timelock_address = _timelock_address;
        transfer_approver_address = _transfer_approver_address;
        multisig_address = _multisig_address;
        transferApprover = ITransferApprover(_transfer_approver_address);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyMinters() {
        require(minters[msg.sender].is_listed == true, "Only minters");
        _;
    }

    /* ========== VIEWS ========== */

    function getMinter(address minter_address)
        external
        view
        returns (Minter memory)
    {
        require(minters[minter_address].is_listed == true, "Minter nonexistant");

        return minters[minter_address];
    }

    function isValidMinter(address minter_address)
        external
        view
        returns (bool)
    {
        return minters[minter_address].is_listed && minters[minter_address].max_mint_amount > 0;
    }

    /* ========== Settings ========== */

    /**
     * @notice Pause Sweep
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpause Sweep
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @notice Set Max Amount of a Minter
     * Update the max mint amount of a user.
     * @param minter_address Address of a user.
     * @param max_mint_amount Amount.
     */
    function setMinterMaxAmount(address minter_address, uint256 max_mint_amount)
        external
        onlyOwner
    {
        require(minters[minter_address].is_listed == true, "Minter nonexistant");
        minters[minter_address].max_mint_amount = max_mint_amount;

        emit MinterUpdated(minter_address, minters[minter_address]);
    }

    /**
     * @notice Minter Enable
     * Enable a user to mint.
     * @param minter_address Address of a user.
     * @param is_enabled True: enabled, False: disabled.
     */
    function setMinterEnabled(address minter_address, bool is_enabled)
        external
        onlyOwner
    {
        require(minters[minter_address].is_listed == true, "Minter nonexistant");
        minters[minter_address].is_mint_enabled = is_enabled;

        emit MinterUpdated(minter_address, minters[minter_address]);
    }

    /**
     * @notice SetTimeLock
     * @param new_timelock Address.
     */
    function setTimelock(address new_timelock) external onlyOwner {
        require(new_timelock != address(0), "Zero address detected");
        timelock_address = new_timelock;

        emit TimelockSet(new_timelock);
    }

    /**
     * @notice Set Transfer Approver
     * @param new_approver Address of a Approver.
     */
    function setTransferApprover(address new_approver) external onlyOwner {
        require(new_approver != address(0), "Zero address detected");
        transfer_approver_address = new_approver;
        transferApprover = ITransferApprover(new_approver);

        emit ApproverSet(new_approver);
    }

    /**
     * @notice Set Multi Singer
     * Add a signer to use in multi sign.
     * @param new_multisig Address of a singer.
     */
    function setMultisig(address new_multisig) external onlyOwner {
        require(new_multisig != address(0), "Zero address detected");
        multisig_address = new_multisig;

        emit MultisigSet(new_multisig);
    }

    /**
     * @notice Transfer OwnerShip
     * @param admin_type.
     */
    function setAdminType(AdminType admin_type) external onlyOwner {
        current_admin_type = admin_type;
        if (admin_type == AdminType.Multisig) {
            transferOwnership(multisig_address);
        } else if (admin_type == AdminType.Governance) {
            transferOwnership(timelock_address);
        } else {
            transferOwnership(DEFAULT_ADMIN_ADDRESS);
        }

        emit AdminTypeSet(admin_type);
    }

    /* ========== Actions ========== */

    /**
     * @notice Mint
     * This function is what other minters will call to mint new tokens
     * @param m_address Address of a minter.
     * @param m_amount Amount for mint.
     */
    function minter_mint(address m_address, uint256 m_amount)
        public
        onlyMinters
        whenNotPaused
    {
        require(minters[msg.sender].is_mint_enabled == true, "Mint is disabled");
        require(minters[msg.sender].minted_amount + m_amount <= minters[msg.sender].max_mint_amount, "Mint cap reached");
        minters[msg.sender].minted_amount += m_amount;
        super._mint(m_address, m_amount);

        emit TokenMinted(msg.sender, m_address, m_amount);
    }

    /**
     * @notice Burn
     * Used by minters when user redeems
     * @param b_amount Amount for burn.
     */
    function minter_burn_from(uint256 b_amount)
        public
        onlyMinters
        whenNotPaused
    {
        require(minters[msg.sender].minted_amount >= b_amount, "burn amount exceeds minted amount");
        super._burn(msg.sender, b_amount);
        minters[msg.sender].minted_amount -= b_amount;

        emit TokenBurned(msg.sender, b_amount);
    }

    /**
     * @notice Add Minter
     * Adds whitelisted minters.
     * @param minter_address Address to be added.
     * @param max_mint_amount Max Amount for mint.
     */
    function addMinter(address minter_address, uint256 max_mint_amount)
        public
        onlyOwner
    {
        require(minter_address != address(0), "Zero address detected");
        require(max_mint_amount > 0, "Zero max mint amount detected");
        require(minters[minter_address].is_listed == false, "Address already exists");
        Minter storage new_minter = minters[minter_address];
        new_minter.is_listed = true;
        new_minter.is_mint_enabled = true;
        new_minter.max_mint_amount = max_mint_amount;
        new_minter.minted_amount = 0;

        emit MinterAdded(minter_address, new_minter);
    }

    /**
     * @notice Remove Minter
     * A minter will be removed from the list.
     * @param minter_address Address to be removed.
     */
    function removeMinter(address minter_address) public onlyOwner {
        require(minter_address != address(0), "Zero address detected");
        require(minters[minter_address].is_listed == true, "Minter nonexistant");
        delete minters[minter_address]; // Delete minter from the mapping

        emit MinterRemoved(minter_address);
    }

    /**
     * @notice Hook that is called before any transfer of Tokens
     * @param from sender address
     * @param to beneficiary address
     * @param amount token amount
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        require(transferApprover.checkTransfer(from, to) == true, "Transfer is not allowed");
        super._beforeTokenTransfer(from, to, amount);
    }
}
