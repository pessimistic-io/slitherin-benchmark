// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20Upgradeable.sol";
import "./AccessControlUpgradeable.sol";

import "./IMintersRegistry.sol";

contract RH2OUpgradeable is
    ERC20Upgradeable,
    IMintersRegistry,
    AccessControlUpgradeable
{
    bytes32 public constant DAO_ROLE = keccak256("DAO");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");
    bytes32 public constant RETIRED_WATER_CREDIT_ROLE =
        keccak256("RETIRED_WATER_CREDIT");
    bytes32 public constant GH2O_ROLE = keccak256("GH2O");
    bytes32 public constant PROPOSAL_REVIEW_ROLE = keccak256("PROPOSAL_REVIEW");

    uint public mintFeeBps;
    address public feeReceiverAddress;

    mapping(address => MinterInfo) private minterInfos;

    bool public transferOpen;

    function initialize(
        uint _mintFeeBps,
        address _feeReceiverAddress,
        address _dao
    ) public initializer {
        __ERC20_init("RH2O", "RH2O");
        __AccessControl_init();

        mintFeeBps = _mintFeeBps;
        feeReceiverAddress = _feeReceiverAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, _dao);
        _grantRole(DAO_ROLE, _dao);
    }

    function mint(uint quantity) external onlyRole(MINTER_ROLE) {
        uint fee = (quantity * mintFeeBps) / 10000;
        _mint(_msgSender(), quantity - fee);
        _mint(feeReceiverAddress, fee);
    }

    function transfer(
        address to,
        uint256 value
    ) public virtual override returns (bool) {
        bool allowedTransferrer = hasRole(DAO_ROLE, _msgSender()) ||
            hasRole(GH2O_ROLE, _msgSender()) ||
            hasRole(PROPOSAL_REVIEW_ROLE, _msgSender());

        require(transferOpen || allowedTransferrer, "Transfer is restricted");
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override returns (bool) {
        bool allowedTransferrer = hasRole(DAO_ROLE, _msgSender()) ||
            hasRole(GH2O_ROLE, _msgSender()) ||
            hasRole(PROPOSAL_REVIEW_ROLE, _msgSender());

        require(transferOpen || allowedTransferrer, "Transfer is restricted");
        return super.transferFrom(from, to, value);
    }

    function setFees(
        uint _mintFeeBps,
        address _feeReceiverAddress
    ) external onlyRole(DAO_ROLE) {
        require(_mintFeeBps >= 0 && _mintFeeBps <= 10000, "Invalid fee");
        mintFeeBps = _mintFeeBps;
        feeReceiverAddress = _feeReceiverAddress;
    }

    function setTransferOpen(bool _transferOpen) external onlyRole(DAO_ROLE) {
        transferOpen = _transferOpen;
    }

    function burn(
        address from,
        uint amount
    ) external onlyRole(RETIRED_WATER_CREDIT_ROLE) {
        _burn(from, amount);
    }

    function setMinter(
        address minter,
        bool _isMinter
    ) external onlyRole(DAO_ROLE) {
        if (_isMinter) {
            _grantRole(MINTER_ROLE, minter);
        } else {
            _revokeRole(MINTER_ROLE, minter);
        }

        emit MinterSet(minter, _isMinter);
    }

    function setMinters(
        address[] calldata minters,
        bool _isMinter
    ) external onlyRole(DAO_ROLE) {
        for (uint i; i < minters.length; i++) {
            if (_isMinter) {
                _grantRole(MINTER_ROLE, minters[i]);
            } else {
                _revokeRole(MINTER_ROLE, minters[i]);
            }
        }

        emit MintersSet(minters, _isMinter);
    }

    function isMinter(address minter) public view returns (bool) {
        return hasRole(MINTER_ROLE, minter);
    }

    function setMinterInfo(
        address minter,
        MinterInfo calldata info
    ) external onlyRole(DAO_ROLE) {
        minterInfos[minter].name = info.name;
        minterInfos[minter].latitude = info.latitude;
        minterInfos[minter].longitude = info.longitude;

        emit MinterInfoSet(minter, info);
    }

    function setMintersInfo(
        address[] calldata minters,
        MinterInfo[] calldata infos
    ) external onlyRole(DAO_ROLE) {
        require(minters.length == infos.length, "Invalid parameters");
        for (uint i; i < minters.length; i++) {
            minterInfos[minters[i]].name = infos[i].name;
            minterInfos[minters[i]].latitude = infos[i].latitude;
            minterInfos[minters[i]].longitude = infos[i].longitude;
        }

        emit MintersInfoSet(minters, infos);
    }

    function getMinterInfo(
        address minter
    ) external view returns (MinterInfo memory) {
        return minterInfos[minter];
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    function balancesOf(address[] calldata accounts) external view returns(uint[] memory accountBalances) {
        accountBalances = new uint[](accounts.length);
        for (uint i; i < accounts.length; i++) {
            accountBalances[i] = balanceOf(accounts[i]);
        }
    }
}

