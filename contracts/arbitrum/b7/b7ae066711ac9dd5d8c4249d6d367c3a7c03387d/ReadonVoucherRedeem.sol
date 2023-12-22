// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./AddressUpgradeable.sol";

interface ReadonNFT {
    function safeMint(address to, uint256 tokenId) external;

    function setClaimed(uint256 tokenId) external;

    function voucherData(
        uint256 tokenId
    ) external returns (Reward memory reward);

    function ownerOf(uint256 tokenId) external view returns (address);

    struct Reward {
        bool status;
    }
}

contract GenesisVoucherRedeem is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address;

    event Redeem(
        address indexed wallet,
        uint256 indexed voucherId,
        uint256 indexed cattoId
    );

    event AddPool(uint256[] cattoPool);

    uint256[] private cattoPool;
    address public catto; //catto
    address public voucher; //voucher

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        voucher = 0x24aBBa077F12F7C0eeE4F9c1FDA116c719410cC5;
        catto = 0x802A3009d53c5DF2A21F008F39a0d8322840F16B;
    }

    function addPool(uint256[] memory _cattoPool) external onlyOwner {
        for (uint i = 0; i < _cattoPool.length; i++) {
            cattoPool.push(_cattoPool[i]);
        }
        emit AddPool(_cattoPool);
    }

    function getRandomCatto() private returns (uint256) {
        require(!msg.sender.isContract(), "call not allowed");
        require(cattoPool.length > 0, "Catto pool is empty");

        uint256 randIndex = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.difficulty))
        ) % cattoPool.length;

        uint256 randomCatto = cattoPool[randIndex];

        cattoPool[randIndex] = cattoPool[cattoPool.length - 1];
        cattoPool.pop();

        return randomCatto;
    }

    function setCatto(address _catto) external onlyOwner {
        catto = _catto;
    }

    function setVoucher(address _voucher) external onlyOwner {
        voucher = _voucher;
    }

    function redeem(uint256 voucherId) public nonReentrant {
        require(
            ReadonNFT(voucher).ownerOf(voucherId) == msg.sender,
            "ReadON:not owner"
        );
        require(
            ReadonNFT(voucher).voucherData(voucherId).status,
            "ReadON:redeemed!"
        );
        ReadonNFT(voucher).setClaimed(voucherId);
        uint256 cattoId = getRandomCatto();
        ReadonNFT(catto).safeMint(msg.sender, cattoId);
        emit Redeem(msg.sender, voucherId, cattoId);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function getPoolSize() public view returns (uint256) {
        return cattoPool.length;
    }

    function clearPool() external onlyOwner {
        delete cattoPool;
    }
}

