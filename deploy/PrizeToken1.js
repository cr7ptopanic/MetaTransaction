module.exports = async ({ getNamedAccounts, deployments }) => {
    const {deploy} = deployments;
    const {deployer} = await getNamedAccounts();

    const owner = '0xc05E5E2215909a229b6ed6479481c14f4691120b'

    await deploy('PrizeToken1', {
      from: deployer,
      args: [
        owner,
      ],
      log: true,
    });
  
  };
  
  module.exports.tags = ['PrizeToken1'];
  