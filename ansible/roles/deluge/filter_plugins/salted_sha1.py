import hashlib


def salted_sha1(raw_password, salt):
    """
    Returns a string of the hexdigest of the given plaintext password and salt
    using the sha1 algorithm.
    """
    hash = hashlib.sha1()
    hash.update('{}{}'.format(salt, raw_password).encode('utf8', 'strict'))
    return hash.hexdigest()


class FilterModule(object):
    ''' A filter to salt sha1-encrypted passwords. '''
    def filters(self):
        return {
          'salted_sha1': salted_sha1
        }
