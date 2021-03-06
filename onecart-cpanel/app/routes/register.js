import Route from '@ember/routing/route';

export default Route.extend({
  model () {
    return {
      ownerid: '',
      password: '',
      recaptcha: ''
    };
  },
  actions: {
    register({ownerid, password, recaptcha}) {
      if (!this.controllerFor('register').validate({ownerid, password, recaptcha})) {
        return;
      }

      Ember.$.ajax('/api/auth/public-enc-key').promise()
        .then(publicKey => {
          const encryptor = new JSEncrypt();
          encryptor.setPublicKey(publicKey);
          const hashedPass = CryptoJS.SHA1(password).toString(CryptoJS.enc.Hex);
          const encPassword = encryptor.encrypt(hashedPass);

          return Ember.$.ajax('/api/apps', {
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify({
              recaptcha,
              ownerid,
              password: encPassword.toString()
            })
          }).promise();
        })
        .then(() => {
          this.controllerFor('application')
              .set('notification', 'The AppID has been sent to your mailbox. Please check!');
          this.transitionTo('login')
        });
    }
  }
});
