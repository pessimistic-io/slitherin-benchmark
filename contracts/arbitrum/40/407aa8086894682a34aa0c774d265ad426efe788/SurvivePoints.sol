//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ECDSAUpgradeable.sol";

import "./ISurvivePoints.sol";
import "./IA3SWalletFactoryV3.sol";
import "./A3SQueue.sol";

contract SurvivePoints is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ERC20Upgradeable,
    ISurvivePoints
{
    address public systemSigner;
    address public factory;
    address public queue;
    mapping(address => bool) public isMinted;
    bool public isClaimSPStart;

    modifier onlyClaimSPStart() {
        require(isClaimSPStart, "A3S: SP Claim Ended");
        _;
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _systemSigner,
        address _factory,
        address _queue
    ) public initializer {
        require(_systemSigner != address(0));
        require(_factory != address(0));
        require(_queue != address(0));
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        systemSigner = _systemSigner;
        factory = _factory;
        queue = _queue;
        emit UpdateSystemSigner(_systemSigner);
    }

    /**
     * @dev See {ISurvivePoints - mintSP}.
     */
    function mintSP(
        address a3sAddress,
        uint256 amount,
        bytes calldata signature
    ) external onlyClaimSPStart {
        require(!isMinted[a3sAddress], "A3S: this a3s address has been minted");
        require(
            IA3SWalletFactoryV3(factory).walletOwnerOf(a3sAddress) ==
                msg.sender,
            "A3S: caller is not a3s owner"
        );
        require(
            isValidToMint(a3sAddress, amount, signature),
            "A3S: Not valid to mint"
        );
        A3SQueue queueContract = A3SQueue(queue);
        uint64 inQueueTime;
        uint64 outQueueTime;
        (, , , , inQueueTime, outQueueTime, ) = queueContract.addressNode(
            a3sAddress
        );
        require(inQueueTime > 0 && outQueueTime == 0, "A3S: Not in queue");

        isMinted[a3sAddress] = true;
        _mint(a3sAddress, amount);
        emit MintSP(msg.sender, a3sAddress, amount);
    }

    /**
     * @dev See {ISurvivePoints - batchMintSP}.
     */
    function batchMintSP(
        address[] memory a3sAddresses,
        uint256[] memory amounts,
        bytes[] calldata signatures
    ) external onlyClaimSPStart {
        uint256 len = a3sAddresses.length;
        require(
            amounts.length == len && signatures.length == len,
            "A3S: address and amount array not matched"
        );
        A3SQueue queueContract = A3SQueue(queue);
        uint64 inQueueTime;
        uint64 outQueueTime;
        for (uint16 i = 0; i < len; i++) {
            require(
                !isMinted[a3sAddresses[i]],
                "A3S: one of the a3s addresses has been minted"
            );
            require(
                IA3SWalletFactoryV3(factory).walletOwnerOf(a3sAddresses[i]) ==
                    msg.sender,
                "A3S: caller is not a3s owner"
            );
            require(
                isValidToMint(a3sAddresses[i], amounts[i], signatures[i]),
                "A3S: Not valid to mint"
            );
            (, , , , inQueueTime, outQueueTime, ) = queueContract.addressNode(
                a3sAddresses[i]
            );
            require(inQueueTime > 0 && outQueueTime == 0, "A3S: Not in queue");

            isMinted[a3sAddresses[i]] = true;
            _mint(a3sAddresses[i], amounts[i]);
            emit MintSP(msg.sender, a3sAddresses[i], amounts[i]);
        }
    }

    function getSignedHash(
        address a3sAddress,
        uint256 amount
    ) public pure returns (bytes32) {
        bytes32 msgHash = keccak256(
            abi.encodePacked("A3S-Verified-SP", a3sAddress, amount)
        );
        bytes32 signedHash = ECDSA.toEthSignedMessageHash(msgHash);
        return signedHash;
    }

    function isValidToMint(
        address a3sAddress,
        uint256 amount,
        bytes calldata signature
    ) public view returns (bool) {
        bytes32 signedHash = getSignedHash(a3sAddress, amount);
        return ECDSA.recover(signedHash, signature) == systemSigner;
    }

    function updateSystemSigner(address _systemSigner) external onlyOwner {
        require(_systemSigner != address(0));
        systemSigner = _systemSigner;
        emit UpdateSystemSigner(_systemSigner);
    }

    function updateClaimSPStart(bool isStart) external onlyOwner {
        isClaimSPStart = isStart;
        emit UpdateClaimSPStart(isStart);
    }

    function projectMintSP(address mintTo, uint256 amount) external onlyOwner {
        _mint(mintTo, amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}

