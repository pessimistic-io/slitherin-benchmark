pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./ISignatureDrop.sol";

/**
 * @title Referral Hub Contract
 */

contract SignatureAssitant is OwnableUpgradeable {
    using SafeMath for uint256;

    address public nft;
    bool private isInitialized = false;

    modifier onlyInitializing() {
        require(!isInitialized, "initialized");
        _;
        isInitialized = true;
    }

    /// @notice Contract constructor
    constructor() public {}

    function initialize(address _nft) public onlyInitializing {
        __Ownable_init();
        nft = _nft;
    }

    function tokensOfAddress(
        address _user
    ) external view returns (uint256[] memory, string[] memory) {
        uint256 totalSupply = ISignatureDrop(nft).totalMinted();
        uint256 userBalance = ISignatureDrop(nft).balanceOf(_user);
        uint256[] memory tokenIds = new uint256[](userBalance);
        string[] memory uris = new string[](userBalance);
        uint256 j = 0;
        for (uint256 i = 0; i < totalSupply; i++) {
            if (ISignatureDrop(nft).ownerOf(i) == _user) {
                tokenIds[j] = i;
                uris[j] = ISignatureDrop(nft).tokenURI(i);
                j++;
            }
        }
        return (tokenIds, uris);
    }

    uint256[49] private __gap;
}

