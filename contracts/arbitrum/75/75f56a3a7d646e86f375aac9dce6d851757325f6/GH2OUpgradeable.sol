// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

contract GH2OUpgradeable is ERC20Upgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant DAO_ROLE = keccak256("DAO");
    bytes32 public constant PROPOSAL_ESCROW_ROLE = keccak256("PROPOSAL_ESCROW");

    IERC20 public rh2O;
    uint public conversionRate;

    bool public isEmergency;

    mapping (address => uint) public unconvertibleBalances;

    event RH2OSet(address rh2O);
    event ConversionRateSet(uint conversionRate);

    event EmergencyModeSet(bool isEmergency);

    function initialize(address _rh2O, address _dao) public initializer {
        __AccessControl_init();
        __ERC20_init("GH2O", "GH2O");

        rh2O = IERC20(_rh2O);
        conversionRate = 100000;

        _grantRole(DEFAULT_ADMIN_ROLE, _dao);
        _grantRole(DAO_ROLE, _dao);
    }

    modifier notEmergency() {
        require(!isEmergency, "Emergency");
        _;
    }

    function convertToGH2O(uint amount) external notEmergency {
        uint gh2OAmount = amount / conversionRate;
        require(gh2OAmount > 0, "Can't convert to 0");
        rh2O.safeTransferFrom(_msgSender(), address(this), amount);
        _mint(_msgSender(), gh2OAmount);
    }

    function convertToRH2O(uint amount) external notEmergency {
        require(amount > 0, "Can't convert 0");
        require(balanceOf(_msgSender()) - amount >= unconvertibleBalances[_msgSender()], "Can't convert unconvertible balance");
        uint rh2OAmount = amount * conversionRate;
        _burn(_msgSender(), amount);
        rh2O.safeTransfer(_msgSender(), rh2OAmount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    function transfer(
        address to,
        uint256 value
    ) public virtual override onlyRole(PROPOSAL_ESCROW_ROLE) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override onlyRole(PROPOSAL_ESCROW_ROLE) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function setRH2O(address _rh2O) external onlyRole(DAO_ROLE) {
        rh2O = IERC20(_rh2O);

        emit RH2OSet(_rh2O);
    }

    function setConversionRate(
        uint _conversionRate
    ) external onlyRole(DAO_ROLE) {
        require(_conversionRate != 0, "Can't set the rate to 0");
        conversionRate = _conversionRate;

        emit ConversionRateSet(conversionRate);
    }

    function setEmergency(bool _isEmergency) external onlyRole(DAO_ROLE) {
        isEmergency = _isEmergency;

        emit EmergencyModeSet(isEmergency);
    }

    function mint(
        address[] calldata receivers,
        uint amount
    ) external onlyRole(DAO_ROLE) {
        require(receivers.length > 0 && amount > 0, "Invalid parameters");
        for (uint i; i < receivers.length; i++) {
            _mint(receivers[i], amount);
            unconvertibleBalances[receivers[i]] += amount;
        }
    }
}

