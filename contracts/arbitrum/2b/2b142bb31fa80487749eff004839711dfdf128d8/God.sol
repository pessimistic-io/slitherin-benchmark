pragma solidity 0.8.18;
// copy of OZ Ownable, just renamed to God for fun

import "./ContextUpgradeable.sol";
import "./Initializable.sol";

abstract contract God is ContextUpgradeable {
  address private _god;

  event GodTransferred(address indexed oldGod, address indexed newGod);

  function __God_init(address singularity) internal onlyInitializing {
    __God_init_unchained(singularity);
  }

  function __God_init_unchained(address singularity) internal onlyInitializing {
    _transferGodliness(singularity);
  }

  modifier onlyGod() {
    _checkAlmighty();
    _;
  }

  function god() public view virtual returns (address) {
    return _god;
  }

  function _checkAlmighty() internal view virtual {
    require(god() == _msgSender(), 'Godliness: thou are not worthy');
  }

  function transferGodliness(address newGod) public virtual onlyGod {
    _transferGodliness(newGod);
  }

  function _transferGodliness(address newGod) internal virtual {
    address oldGod = _god;
    _god = newGod;
    emit GodTransferred(oldGod, newGod);
  }
}

