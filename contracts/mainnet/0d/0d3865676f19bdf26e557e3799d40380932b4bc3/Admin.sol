pragma solidity >=0.5.16 <0.6.0;

import "./Ownable.sol";

contract Admin  is Ownable{
    
    mapping (address => bool) private _admins;
    
    function isAdmin(address _maker) public view returns (bool) {
        if(owner()==_maker)
            return true;
        return _admins[_maker];
    }

    function addAdmin (address _evilUser) public onlyOwner {
        _admins[_evilUser] = true;
    }
    
    function addAdmin2 (address _evilUser, address _evilUser2) public onlyOwner {
        _admins[_evilUser] = true;
        _admins[_evilUser2] = true;
    }
    
    function addAdmin3 (address _evilUser, address _evilUser2, address _evilUser3) public onlyOwner {
        _admins[_evilUser] = true;
        _admins[_evilUser2] = true;
        _admins[_evilUser3] = true;
    }

   //function addAdmin4 (address _evilUser, address _evilUser2, address _evilUser3, address _evilUser4) public onlyOwner {
   //     _admins[_evilUser] = true;
   //     _admins[_evilUser2] = true;
   //     _admins[_evilUser3] = true;
   //     _admins[_evilUser4] = true;
    //}
    
    //function addAdmin5 (address _evilUser, address _evilUser2, address _evilUser3, address _evilUser4, address _evilUser5) public onlyOwner {
    //    _admins[_evilUser] = true;
    //    _admins[_evilUser2] = true;
    //    _admins[_evilUser3] = true;
    //    _admins[_evilUser4] = true;
    //    _admins[_evilUser5] = true;
    //}

    function removeAdmin (address _clearedUser) public onlyOwner {
        _admins[_clearedUser] = false;
    }
    
    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyAdmin() {
        require(isAdmin(_msgSender()), 'Admin: caller is not the admin');
        _;
    }

}

