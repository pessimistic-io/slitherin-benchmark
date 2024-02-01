import "./NiftyEnumerable.sol";
import "./Ownable.sol";

contract AvatarETH is NiftyEnumerable, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        string memory uri,
        address _royaltyWallet
    ) NiftyEnumerable(uri, name, symbol, tx.origin) {
        _setRoyaltyWallet(_royaltyWallet);
    }

    function mint(address to, uint256 id) public isMinter returns (uint256) {
        _mint(to, id);
    }
}

