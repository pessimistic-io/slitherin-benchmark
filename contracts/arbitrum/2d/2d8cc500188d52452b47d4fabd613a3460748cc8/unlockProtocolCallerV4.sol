// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IUnlockProtocol.sol";
import "./IUnlockFact.sol";
import "./IPurchaseHook.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";


contract unlockProtocolCallerV4 is OwnableUpgradeable, ReentrancyGuardUpgradeable {

    /// @notice Emitted when `MINT_FEE` is not passed in as msg.value during `mint()`
    error InvalidFee();

    /// @notice Emitted when ether transfer reverted
    error TransferFailed();

    event LockCreated(address indexed lockAddress);
    event MintFeePaid(uint256 mintFee, address mintFeePayer, address mintFeeRecipient);
    event withdrawComplete(address[] lockAddress, 
        address[] _tokenAddress, 
        address payable[] _recipient, 
        uint256[] _amount
    );
    event mintValuesSet(uint256 _mintFee, address _mintFeeRecipient);
    
    /// @notice Mint Fee
    uint256 public MINT_FEE;


    /// @notice Mint Fee Recipient
    address payable public MINT_FEE_RECIPIENT;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
        
    }

    function initialize() initializer public {
        __Ownable_init();
    }
    
    function setMintValues(uint256 _mintFee, address payable _mintFeeRecipient) public onlyOwner {
        MINT_FEE = _mintFee;
        MINT_FEE_RECIPIENT = _mintFeeRecipient;
        emit mintValuesSet(_mintFee, _mintFeeRecipient);
    }

    function createLock(
        address _unlock,
        address _address,
        address _owner,
        uint256 _time,
        address _tokenAddress,
        uint256 _price,
        uint256 _keys,
        string memory _lockName,
        address _referrer,
        uint256 _feeBasisPoint
    ) public onlyOwner returns (address) {
        // goerli: 0x627118a4fB747016911e5cDA82e2E77C531e8206
        // mumbai: 0x1FF7e338d5E582138C46044dc238543Ce555C963
        IUnlockFact unlock = IUnlockFact(_unlock);
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,uint256,address,uint256,uint256,string)",
            _address,
            _time,
            _tokenAddress,
            _price,
            _keys,
            _lockName
        );
        address unlockAddress = unlock.createUpgradeableLock(data);
        emit LockCreated(unlockAddress);
        IUnlockProtocol unlockProtocol = IUnlockProtocol(unlockAddress);
        unlockProtocol.setReferrerFee(_referrer, _feeBasisPoint);
        unlockProtocol.addLockManager(_owner);
        unlockProtocol.setOwner(_owner);
        return unlockAddress;
    }

    function updateUnlockProtocolKeyPricing(
        address _lockAddress,
        address _tokenAddress,
        uint256 _keyPrice
    ) public onlyOwner {
        // instance of the unlock lock contract
        IUnlockProtocol unlockProtocol = IUnlockProtocol(_lockAddress);

        // Call the updateKeyPricing function on the lock contract
        unlockProtocol.updateKeyPricing(_keyPrice, _tokenAddress);
    }

    function renounceLockManager(address _lockAddress) public onlyOwner {
        IUnlockProtocol unlockProtocol = IUnlockProtocol(_lockAddress);
        unlockProtocol.renounceLockManager();
    }

    function setLockValues(
        address _lockAddress,
        string calldata _lockName,
        string calldata _lockSymbol,
        string calldata _baseTokenURI,
        uint256 _newExpirationDuration,
        uint256 _maxNumberOfKeys,
        uint256 _maxKeysPerAcccount,
        address _keyGranter
    ) public onlyOwner {
        IUnlockProtocol unlockProtocol = IUnlockProtocol(_lockAddress);
        unlockProtocol.setLockMetadata(_lockName, _lockSymbol, _baseTokenURI);
        bytes32 keyGranterRole = keccak256(abi.encodePacked("KEY_GRANTER"));
        unlockProtocol.grantRole(keyGranterRole, _keyGranter);
        unlockProtocol.updateLockConfig(
            _newExpirationDuration,
            _maxNumberOfKeys,
            _maxKeysPerAcccount
        );
    }

    function setPassword(
        address _lockAddress,
        address _signer,
        address _passHook
    ) public onlyOwner {
        IPurchaseHook purchaseHook = IPurchaseHook(_passHook);
        purchaseHook.setSigner(_lockAddress, _signer);
        IUnlockProtocol unlockProtocol = IUnlockProtocol(_lockAddress);
        unlockProtocol.setEventHooks(
            _passHook,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }

    function batch(
        address[] memory _lockAddress,
        string[] memory _lockName,
        string[] memory _lockSymbol,
        string[] memory _baseTokenURI,
        address[] memory _referrer,
        uint256[] memory _feeBasisPoint,
        address[] memory passHook,
        address[] memory _tokenAddress,
        uint256[] memory _keyPrice,
        uint256 size
    ) public onlyOwner {
        for (uint256 i = 0; i < size; i++) {
            IUnlockProtocol unlockProtocol = IUnlockProtocol(_lockAddress[i]);
            unlockProtocol.setLockMetadata(
                _lockName[i],
                _lockSymbol[i],
                _baseTokenURI[i]
            );
            unlockProtocol.setReferrerFee(_referrer[i], _feeBasisPoint[i]);
            unlockProtocol.updateKeyPricing(_keyPrice[i], _tokenAddress[i]);
            unlockProtocol.setEventHooks(
                passHook[i],
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            );
        }
    }

    function burn(
        address _lockAddress,
        uint256 size,
        uint256[] memory _tokenId
    ) public onlyOwner {
        IUnlockProtocol unlockProtocol = IUnlockProtocol(_lockAddress);
        for (uint256 i = 0; i < size; i++) {
            unlockProtocol.burn(_tokenId[i]);
        }
    }

    function updateLock(
        address _lockAddress,
        uint256 _keyPrice,
        address _tokenAddress,
        string memory _lockName,
        string memory _lockSymbol,
        string memory _baseTokenURI,
        uint256 _newExpirationDuration,
        uint256 _maxNumberOfKeys,
        uint256 _maxKeysPerAcccount
    ) public onlyOwner {
        IUnlockProtocol unlockProtocol = IUnlockProtocol(_lockAddress);
        unlockProtocol.updateKeyPricing(_keyPrice, _tokenAddress);
        unlockProtocol.setLockMetadata(_lockName, _lockSymbol, _baseTokenURI);
        unlockProtocol.updateLockConfig(
            _newExpirationDuration,
            _maxNumberOfKeys,
            _maxKeysPerAcccount
        );
    }

    function grantKeyToMultipleAddresses(
        address[] memory lockAddress,
        address[] memory walletAddress,
        uint256[] memory time
    ) public onlyOwner {
        if (time[0] == 0) {
            time[0] = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        }
        else {
            time[0] = time[0] + block.timestamp;
        }
        for (uint256 i = 0; i < lockAddress.length; i++) {
            IUnlockProtocol unlockProtocol = IUnlockProtocol(lockAddress[i]);
            unlockProtocol.grantKeys(walletAddress, time, walletAddress);
        }
    }

    function mintKey(
        address[] memory lockAddress,
        address[] memory walletAddress,
        uint256[] memory time
    ) public payable nonReentrant {
        if (msg.value != MINT_FEE) {
            /* revert InvalidFee(); */
            assembly {
                mstore(0x00, 0x58d620b3) // InvalidFee()
                revert(0x1c, 0x04)
            }
        }

        if (time[0] == 0) {
            time[0] = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        }
        else {
            time[0] = time[0] + block.timestamp;
        }
        for (uint256 i = 0; i < lockAddress.length; i++) {
            IUnlockProtocol unlockProtocol = IUnlockProtocol(lockAddress[i]);
            unlockProtocol.grantKeys(walletAddress, time, walletAddress);
        }
        _payMintFee();
    }

    function _payMintFee() internal {
        (bool success, ) = MINT_FEE_RECIPIENT.call{value: MINT_FEE}("");
        /* if (!success) revert TransferFailed(); */
        assembly {
            if iszero(success) {
                mstore(0x00, 0x90b8ec18) // TransferFailed()
                revert(0x1c, 0x04)
            }
        }

        emit MintFeePaid(MINT_FEE, msg.sender, MINT_FEE_RECIPIENT);
    }

    function transferKey(address lockAddress, address _from, address _to, uint256 tokenId) public onlyOwner {
        IUnlockProtocol unlockProtocol = IUnlockProtocol(lockAddress);
        unlockProtocol.setKeyManagerOf(tokenId, _to);
        unlockProtocol.safeTransferFrom(_from, _to, tokenId);

    }
    
    function withdraw(
        address[] memory lockAddress, 
        address[] memory _tokenAddress, 
        address payable[] memory _recipient, 
        uint256[] memory _amount
    ) public onlyOwner {

        for (uint256 i = 0; i < lockAddress.length; i++) {
            IUnlockProtocol unlockProtocol = IUnlockProtocol(lockAddress[i]);
            unlockProtocol.withdraw(_tokenAddress[i], _recipient[i], _amount[i]);
        }
        emit withdrawComplete(lockAddress, _tokenAddress, _recipient, _amount);

    }

}

