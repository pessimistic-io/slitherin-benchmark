// SPDX-License-Identifier: MIT LICENSE

pragma solidity >0.8.0;
import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IBOO.sol";
import "./BOOBase.sol";
import "./IHideNSeek.sol";
import "./IPABStake.sol";

contract BOO is IBOO, ERC20Upgradeable, OwnableUpgradeable, BOOBase {
    function initialize(uint256 cap_) public initializer {
        __ERC20_init("BOO", "BOO");
        __Ownable_init();

        _cap = cap_;
    }

    /**
     * mints $BOO to a recipient
     * @param to the recipient of the $BOO
     * @param amount the amount of $BOO to mint
     */
    function mint(address to, uint256 amount) external {
        require(controllers[msg.sender], "Only controllers can mint");
        _mint(to, amount);
        for (uint256 i = 0; i < fundingAddresses.length; i++) {
            _mint(
                fundingAddresses[i],
                (amount * fundingAllocation[fundingAddresses[i]]) / 100
            );
        }
    }

    /**
     * burns $BOO from a holder
     * @param from the holder of the $BOO
     * @param amount the amount of $BOO to burn
     */
    function burn(address from, uint256 amount) external {
        require(controllers[msg.sender], "Only controllers can burn");
        _burn(from, amount);
    }

    function cap() external view returns (uint256) {
        return _cap;
    }

    function capUpdate(uint256 _newCap) public onlyOwner {
        _cap = _newCap;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            require(
                totalSupply() + amount <= _cap,
                "ERC20Capped: cap exceeded"
            );
        }
    }

    /**
     * enables an address to mint / burn
     * @param controller the address to enable
     */
    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
    }

    /**
     * disables an address from minting / burning
     * @param controller the address to disbale
     */
    function removeController(address controller) external onlyOwner {
        controllers[controller] = false;
    }

    function isController(address _controller) public view returns (bool) {
        return controllers[_controller];
    }

    function setAllocationAddress(address fundingAddress, uint256 allocation)
        external
        onlyOwner
    {
        if (fundingAllocation[fundingAddress] != 0) {
            fundingAddresses.push(fundingAddress);
        }
        fundingAllocation[fundingAddress] = allocation;
    }

    function removeAllocationAddress(address fundingAddress)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < fundingAddresses.length; i++) {
            if (fundingAddress == fundingAddresses[i]) {
                fundingAddresses[i] = fundingAddresses[
                    fundingAddresses.length - 1
                ];
                fundingAddresses.pop();
            }
        }
    }
}

