//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface MintableToken is IERC20 {
    function mint(uint256 amount, address eth_address) external;
    function burn(address from, uint256 amount) external;
}

contract Token is ERC20, MintableToken {
    constructor() ERC20("Token", "TON") {}

    function mint(uint256 amount, address eth_address) public {
        _mint(eth_address, amount);
    }

    function burn(address from, uint256 amount) external {
      _burn(from, amount);
    }
}
