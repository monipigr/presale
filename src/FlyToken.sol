// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract FlyToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 30000000 * 1e18; // 30M

    constructor() ERC20("Fly Token", "FLY") {
        _mint(msg.sender, INITIAL_SUPPLY);
        approve(address(this), INITIAL_SUPPLY);
    }
}
