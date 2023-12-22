// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {ERC20} from "./ERC20.sol";
import {IERC677Receiver} from "./IERC677Receiver.sol";
import {Ownable} from "./Ownable.sol";

/*
O)))))                     O))                  O)                                     O))                         
O))   O))                  O))                 O) ))                                O))   O))           O)         
O))    O))   O))    O) O)))O))  O))           O)  O))       O))      O))           O))          O))       O)) O))  
O))    O)) O))  O))  O))   O)) O))           O))   O))    O))  O)) O)   O))        O))        O))  O)) O)) O))  O))
O))    O))O))   O))  O))   O)O))            O)))))) O))  O))   O))O))))) O))       O))       O))    O))O)) O))  O))
O))   O)) O))   O))  O))   O)) O))         O))       O))  O))  O))O)                O))   O)) O))  O)) O)) O))  O))
O)))))      O)) O)))O)))   O))  O))       O))         O))     O))   O))))             O))))     O))    O))O)))  O))
                                                           O))                                                     */

/**
 * @title DarkAgeCoin
 * @notice The currency of the medieval realm, fueling its mischievous economy.
 * @dev A token contract representing the DarkAgeCoin, the main currency of the enigmatic medieval world.
 * DarkAgeCoin is the lifeblood of commerce and intrigue in the realm, and is wielded by peasants,
 * knights, and nobility alike. Governed by the unwritten laws of power and ambition, this digital
 * artifact empowers its bearer to partake in the realm's trade, plunder, and prosperity.
 */
contract DarkAgeCoin is ERC20, Ownable {
    address public realm;

    event RealmUpdated(address indexed previousRealm, address indexed newRealm);

    modifier onlyRealm() {
        require(msg.sender == realm, "DarkAgeCoin: Only the Realm can call this function.");
        _;
    }

    constructor(string memory _tokenName, string memory _tokenSymbol, uint256 _totalSupply)
        ERC20(_tokenName, _tokenSymbol)
    {
        _mint(msg.sender, _totalSupply);
    }

    function forge(address _to, uint256 _amount) external onlyRealm {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyRealm {
        _burn(_from, _amount);
    }

    function transferAndCall(address _to, uint256 _value, bytes memory _data) public returns (bool) {
        super.transfer(_to, _value);
        if (isContract(_to)) {
            contractFallback(msg.sender, _to, _value, _data);
        }
        return true;
    }

    function transferAndCallFrom(address _sender, address _to, uint256 _value, bytes memory _data)
        internal
        returns (bool)
    {
        _transfer(_sender, _to, _value);
        if (isContract(_to)) {
            contractFallback(_sender, _to, _value, _data);
        }
        return true;
    }

    function contractFallback(address _sender, address _to, uint256 _value, bytes memory _data) internal {
        IERC677Receiver receiver = IERC677Receiver(_to);
        receiver.onTokenTransfer(_sender, _value, _data);
    }

    function setRealm(address _realm) external onlyOwner {
        address previousRealm = realm;
        realm = _realm;
        emit RealmUpdated(previousRealm, _realm);
    }

    function isContract(address _addr) internal view returns (bool hasCode) {
        uint256 length;
        assembly {
            length := extcodesize(_addr)
        }
        return length > 0;
    }
}

