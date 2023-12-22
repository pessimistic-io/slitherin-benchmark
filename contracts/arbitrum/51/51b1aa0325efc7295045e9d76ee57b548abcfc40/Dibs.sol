// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AccessControlUpgradeable.sol";

contract Dibs is AccessControlUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public PROJECT_ID; // keccak256(chainId + contractAddress)

    bytes32 public constant DIBS = keccak256("DIBS");
    bytes32 public constant SETTER = keccak256("SETTER");

    address public muonInterface; // this address can withdraw tokens from this contract on behalf of a user

    /** DIBS code */
    mapping(address => bytes32) public addressToCode;
    mapping(bytes32 => address) public codeToAddress;
    mapping(bytes32 => string) public codeToName;
    mapping(address => address) public parents;

    mapping(address => mapping(address => uint256)) public claimedBalance; // token => user => claimed balance

    // a total of two levels of parents are allowed
    uint32 public SCALE;
    uint32 public grandparentPercentage;
    uint32 public dibsPercentage;

    address public dibsLottery;
    address public wethPriceFeed; // chainLink compatible price feed

    uint32 public firstRoundStartTime;
    uint32 public roundDuration;

    uint32 public referrerPercentage;
    uint32 public refereePercentage;

    bytes32 public constant BLACKLIST_SETTER = keccak256("BLACKLIST_SETTER");
    mapping(address => bool) public blacklisted;

    // * these values are in SCALE units (1e6) and should be divided by SCALE to get the actual percentage
    // the sum of these values should be 1e6

    error CodeAlreadyExists();
    error CodeDoesNotExist();
    error ZeroValue();
    error BalanceTooLow();
    error NotMuonInterface();
    error Blacklisted();

    // initializer
    function initialize(
        address admin_,
        address setter_,
        address dibsLottery_,
        address wethPriceFeed_,
        uint32 firstRoundStartTime_,
        uint32 roundDuration_
    ) public initializer {
        __AccessControl_init();
        __Dibs_init(
            admin_,
            setter_,
            dibsLottery_,
            wethPriceFeed_,
            firstRoundStartTime_,
            roundDuration_
        );

        PROJECT_ID = keccak256(
            abi.encodePacked(uint256(block.chainid), address(this))
        );
    }

    function __Dibs_init(
        address admin_,
        address setter_,
        address dibsLottery_,
        address wethPriceFeed_,
        uint32 firstRoundStartTime_,
        uint32 roundDuration_
    ) internal onlyInitializing {
        if (
            admin_ == address(0) ||
            setter_ == address(0) ||
            dibsLottery_ == address(0) ||
            wethPriceFeed_ == address(0)
        ) {
            revert ZeroValue();
        }

        _setupRole(DEFAULT_ADMIN_ROLE, admin_);
        _setupRole(SETTER, setter_);

        // register DIBS code
        addressToCode[address(this)] = DIBS;
        codeToAddress[DIBS] = address(this);
        codeToName[DIBS] = "DIBS";

        SCALE = 1e6;
        referrerPercentage = 70e4;
        refereePercentage = 0;
        grandparentPercentage = 25e4;
        dibsPercentage = 5e4;

        dibsLottery = dibsLottery_;
        wethPriceFeed = wethPriceFeed_;

        firstRoundStartTime = firstRoundStartTime_;
        roundDuration = roundDuration_;
    }

    // get code name
    function getCodeName(address user) public view returns (string memory) {
        return codeToName[addressToCode[user]];
    }

    function getCode(string memory name) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    function getAddress(string memory name) public view returns (address) {
        return codeToAddress[getCode(name)];
    }

    /** =========== PUBLIC FUNCTIONS =========== */

    event Register(
        address indexed _address,
        bytes32 indexed _code,
        string _name,
        address _parent
    );

    /// @notice register a new code
    /// @param name the name of the code
    /// @param parentCode the parent to set for the code
    function register(string memory name, bytes32 parentCode) public virtual {
        address user = msg.sender;

        // revert if code is zero
        if (bytes(name).length == 0) {
            revert ZeroValue();
        }

        bytes32 code = getCode(name);

        // revert if code is already assigned to another address
        if (codeToAddress[code] != address(0)) {
            revert CodeAlreadyExists();
        }

        // revert if address is already assigned to a code
        if (addressToCode[user] != bytes32(0)) {
            revert CodeAlreadyExists();
        }

        address parentAddress = codeToAddress[parentCode];

        // validate if parent code exists
        if (parentAddress == address(0)) {
            revert CodeDoesNotExist();
        }

        // register the code for the user
        addressToCode[user] = code;
        codeToAddress[code] = user;
        codeToName[code] = name;
        parents[user] = parentAddress;

        emit Register(user, code, name, parents[user]);
    }

    /** =========== MUON INTERFACE RESTRICTED FUNCTIONS =========== */

    /// @notice withdraw tokens from this contract on behalf of a user
    /// @dev this function is called by the muon interface,
    /// muon interface should validate the accumulative balance
    /// @param from address of the user
    /// @param token address of the token
    /// @param amount amount of tokens to withdraw
    /// @param to address to send the tokens to
    /// @param accumulativeBalance accumulated balance of the user
    function claim(
        address from,
        address token,
        uint256 amount,
        address to,
        uint256 accumulativeBalance
    ) external onlyMuonInterface {
        _claim(token, from, amount, to, accumulativeBalance);
    }

    /** =========== RESTRICTED FUNCTIONS =========== */

    // set/unset list of blacklisted addresses
    event SetBlacklisted(address[] _addresses, bool _isBlacklisted);

    /// @notice set/unset list of blacklisted addresses
    /// @param _addresses : list of addresses to set/unset
    /// @param _isBlacklisted : true to set, false to unset
    function setBlacklisted(
        address[] calldata _addresses,
        bool _isBlacklisted
    ) external onlyRole(BLACKLIST_SETTER) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            blacklisted[_addresses[i]] = _isBlacklisted;
        }

        emit SetBlacklisted(_addresses, _isBlacklisted);
    }

    // set muonInterface address
    event SetMuonInterface(address _old, address _new);

    function setMuonInterface(
        address _muonInterface
    ) external onlyRole(SETTER) {
        emit SetMuonInterface(muonInterface, _muonInterface);
        muonInterface = _muonInterface;
    }

    // set grandparent and dibs percentage
    event SetPercentages(
        uint32 _referrerPercentage,
        uint32 _refereePercentage,
        uint32 _grandparentPercentage,
        uint32 _dibsPercentage
    );

    function setPercentages(
        uint32 _refereePercentage,
        uint32 _referrerPercentage,
        uint32 _grandparentPercentage,
        uint32 _dibsPercentage
    ) external onlyRole(SETTER) {
        refereePercentage = _refereePercentage;
        referrerPercentage = _referrerPercentage;
        grandparentPercentage = _grandparentPercentage;
        dibsPercentage = _dibsPercentage;

        emit SetPercentages(
            _refereePercentage,
            _referrerPercentage,
            _grandparentPercentage,
            _dibsPercentage
        );
    }

    function recoverERC20(
        address token,
        uint256 amount,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }

    event SetParent(address _user, address _parent);

    function setParent(address user, address parent) external onlyRole(SETTER) {
        emit SetParent(user, parent);
        _setParent(user, parent);
    }

    // todo: set price feed and dibsLottery

    /** =========== INTERNAL FUNCTIONS =========== */

    function _setParent(address user, address parent) internal {
        parents[user] = parent;
        emit SetParent(user, parent);
    }

    event Claim(
        address indexed _user,
        uint256 _amount,
        address _to,
        address _token
    );

    /// @notice transfer tokens from user to to
    /// @dev accumulativeBalance should be passed from a trusted source (e.g. Muon)
    /// @param token token to transfer
    /// @param from user to transfer from
    /// @param amount amount to transfer
    /// @param to user to transfer to

    function _claim(
        address token,
        address from,
        uint256 amount,
        address to,
        uint256 accumulativeBalance
    ) internal notBlacklisted(from) {
        uint256 remainingBalance = accumulativeBalance -
            claimedBalance[token][from];

        // revert if balance is too low
        if (remainingBalance < amount) {
            revert BalanceTooLow();
        }

        // update claimed balance
        claimedBalance[token][from] += amount;

        IERC20Upgradeable(token).safeTransfer(to, amount);
        emit Claim(from, amount, to, token);
    }

    // ** =========== MODIFIERS =========== **

    modifier onlyMuonInterface() {
        if (msg.sender != muonInterface) revert NotMuonInterface();
        _;
    }

    modifier notBlacklisted(address user) {
        if (blacklisted[user]) revert Blacklisted();
        _;
    }
}

