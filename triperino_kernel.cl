#define SALT_LEN 2
#define TRUNCATE_LEN 10

#define VALID_MIN 46
#define VALID_MAX 122
#define VALID_LEN VALID_MAX - VALID_MIN

#define REPLACE_MIN 58
#define REPLACE_MAX 64
#define REPLACE_OFFSET 7

#define REPLACE_MIN_2 91
#define REPLACE_MAX_2 96
#define REPLACE_OFFSET_2 6

#define MAX_PW_LEN 8

inline int
ascii_to_bin(__private char ch)
{
	char sch = ch;
	int retval;

	retval = sch - '.';
	if (sch >= 'A') {
		retval = sch - ('A' - 12);
		if (sch >= 'a')
			retval = sch - ('a' - 38);
	}
	retval &= 0x3f;

	return(retval);
}

inline void
setup_salt(__private uint salt,
           __private uint *data_saltbits,
           __private uint *data_old_salt)

{
	uint	obit, saltbit, saltbits;
	int	i;

	if (salt == *data_old_salt)
		return;
	*data_old_salt = salt;

	saltbits = 0;
	saltbit = 1;
	obit = 0x800000;
	for (i = 0; i < 24; i++) {
		if (salt & saltbit)
			saltbits |= obit;
		saltbit <<= 1;
		obit >>= 1;
	}
	*data_saltbits = saltbits;
    #ifdef debug
    printf("%u\n", *data_saltbits);
    #endif
}

inline int des_setkey(__global uint *key_perm_maskl_flat,
                  __global uint *key_perm_maskr_flat,
                  __global uint *comp_maskl_flat,
                  __global uint *comp_maskr_flat,
                  __private char *key, 
                  __private uint *data_en_keysl,
                  __private uint *data_en_keysr,
                  __private uint *data_de_keysl,
                  __private uint *data_de_keysr,
                  __private uint *data_old_rawkey0,
                  __private uint *data_old_rawkey1,
                  __private char *data_output
                 )
{
    uchar	key_shifts[16] = {
        1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1
    };

    uint	k0, k1, rawkey0, rawkey1;
	int	shifts, round;
    rawkey0 =
		(uint)(uchar)key[3] |
		((uint)(uchar)key[2] << 8) |
		((uint)(uchar)key[1] << 16) |
		((uint)(uchar)key[0] << 24);
    rawkey1 =
		(uint)(uchar)key[7] |
		((uint)(uchar)key[6] << 8) |
		((uint)(uchar)key[5] << 16) |
		((uint)(uchar)key[4] << 24);

	if ((rawkey0 | rawkey1)
	    && rawkey0 == *data_old_rawkey0
	    && rawkey1 == *data_old_rawkey1) {
		/*
		 * Already setup for this key.
		 * This optimisation fails on a zero key (which is weak and
		 * has bad parity anyway) in order to simplify the starting
		 * conditions.
		 */
		return(0);
	}

	*data_old_rawkey0 = rawkey0;
	*data_old_rawkey1 = rawkey1;
    #ifdef debuf
    printf("%u\n", *data_old_rawkey0);
    printf("%u\n", *data_old_rawkey1);
    #endif


	/*
	 *	Do key permutation and split into two 28-bit subkeys.
     *
	 */
    /* converting from 2d to flat array */
	k0 = key_perm_maskl_flat[(0*128) + (rawkey0 >> 25)]
	   | key_perm_maskl_flat[(1*128) + ((rawkey0 >> 17) & 0x7f)]
	   | key_perm_maskl_flat[(2*128) + ((rawkey0 >> 9) & 0x7f)]
	   | key_perm_maskl_flat[(3*128) + ((rawkey0 >> 1) & 0x7f)]
	   | key_perm_maskl_flat[(4*128) + (rawkey1 >> 25)]
	   | key_perm_maskl_flat[(5*128) + ((rawkey1 >> 17) & 0x7f)]
	   | key_perm_maskl_flat[(6*128) + ((rawkey1 >> 9) & 0x7f)]
	   | key_perm_maskl_flat[(7*128) + ((rawkey1 >> 1) & 0x7f)];
	k1 = key_perm_maskr_flat[(0*128) + (rawkey0 >> 25)]
	   | key_perm_maskr_flat[(1*128) + ((rawkey0 >> 17) & 0x7f)]
	   | key_perm_maskr_flat[(2*128) + ((rawkey0 >> 9) & 0x7f)]
	   | key_perm_maskr_flat[(3*128) + ((rawkey0 >> 1) & 0x7f)]
	   | key_perm_maskr_flat[(4*128) + (rawkey1 >> 25)]
	   | key_perm_maskr_flat[(5*128) + ((rawkey1 >> 17) & 0x7f)]
	   | key_perm_maskr_flat[(6*128) + ((rawkey1 >> 9) & 0x7f)]
	   | key_perm_maskr_flat[(7*128) + ((rawkey1 >> 1) & 0x7f)];
    #ifdef debug
    printf("%u\n", key_perm_maskl_flat[(0*128) + rawkey0 >> 25]);
    printf("%u\n", key_perm_maskl_flat[(3*128) + ((rawkey0 >> 1) & 0x7f)]);
    #endif

	/*
	 *	Rotate subkeys and do compression permutation.
	 */
	shifts = 0;
	for (round = 0; round < 16; round++) {
		uint	t0, t1;

		shifts += key_shifts[round];

		t0 = (k0 << shifts) | (k0 >> (28 - shifts));
		t1 = (k1 << shifts) | (k1 >> (28 - shifts));
		data_de_keysl[15 - round] =
		data_en_keysl[round] = comp_maskl_flat[(0*128) + ((t0 >> 21) & 0x7f)]
				| comp_maskl_flat[(1*128) + ((t0 >> 14) & 0x7f)]
				| comp_maskl_flat[(2*128) + ((t0 >> 7) & 0x7f)]
				| comp_maskl_flat[(3*128) + (t0 & 0x7f)]
				| comp_maskl_flat[(4*128) + ((t1 >> 21) & 0x7f)]
				| comp_maskl_flat[(5*128) + ((t1 >> 14) & 0x7f)]
				| comp_maskl_flat[(6*128) + ((t1 >> 7) & 0x7f)]
				| comp_maskl_flat[(7*128) + (t1 & 0x7f)];

		data_de_keysr[15 - round] =
		data_en_keysr[round] = comp_maskr_flat[(0*128) + (t0 >> 21) & 0x7f]
				| comp_maskr_flat[(1*128) + ((t0 >> 14) & 0x7f)]
				| comp_maskr_flat[(2*128) + ((t0 >> 7) & 0x7f)]
				| comp_maskr_flat[(3*128) + (t0 & 0x7f)]
				| comp_maskr_flat[(4*128) + ((t1 >> 21) & 0x7f)]
				| comp_maskr_flat[(5*128) + ((t1 >> 14) & 0x7f)]
				| comp_maskr_flat[(6*128) + ((t1 >> 7) & 0x7f)]
				| comp_maskr_flat[(7*128) + (t1 & 0x7f)];
	}
	return(0);

}

inline int
do_des(__global uchar *m_sbox_flat,
       __global uint *psbox_flat,
       __global uint *ip_maskl_flat,
       __global uint *ip_maskr_flat,
       __global uint *fp_maskl_flat,
       __global uint *fp_maskr_flat,
       __private uint l_in, 
       __private uint r_in, 
       __private uint *l_out,
       __private uint *r_out,
	   __private int count,
       __private uint *data_saltbits,
       __private uint *data_en_keysl,
       __private uint *data_en_keysr,
       __private uint *data_de_keysl,
       __private uint *data_de_keysr
        )
{
    /*
	 *	l_in, r_in, l_out, and r_out are in pseudo-"big-endian" format.
	 */
	uint	l, r, *kl, *kr, *kl1, *kr1;
	uint	f, r48l, r48r, saltbits;
	int	round;
    
    if (count == 0) {
    return(1);
	} else if (count > 0) {
		/*
		 * Encrypting
		 */
		kl1 = data_en_keysl;
		kr1 = data_en_keysr;
	} else {
		/*
		 * Decrypting
		 */
		count = -count;
		kl1 = data_de_keysl;
		kr1 = data_de_keysr;
	}

   	/*
	 *	Do initial permutation (IP).
	 */
	l = ip_maskl_flat[(0*256) + (l_in >> 24)]
	  | ip_maskl_flat[(1*256) + ((l_in >> 16) & 0xff)]
	  | ip_maskl_flat[(2*256) + ((l_in >> 8) & 0xff)]
	  | ip_maskl_flat[(3*256) + (l_in & 0xff)]
	  | ip_maskl_flat[(4*256) + (r_in >> 24)]
	  | ip_maskl_flat[(5*256) + ((r_in >> 16) & 0xff)]
	  | ip_maskl_flat[(6*256) + ((r_in >> 8) & 0xff)]
	  | ip_maskl_flat[(7*256) + (r_in & 0xff)];
	r = ip_maskr_flat[(0*256) + (l_in >> 24)]
	  | ip_maskr_flat[(1*256) + ((l_in >> 16) & 0xff)]
	  | ip_maskr_flat[(2*256) + ((l_in >> 8) & 0xff)]
	  | ip_maskr_flat[(3*256) + (l_in & 0xff)]
	  | ip_maskr_flat[(4*256) + (r_in >> 24)]
	  | ip_maskr_flat[(5*256) + ((r_in >> 16) & 0xff)]
	  | ip_maskr_flat[(6*256) + ((r_in >> 8) & 0xff)]
	  | ip_maskr_flat[(7*256) + (r_in & 0xff)];

	saltbits = *data_saltbits;
	while (count--) {
		/*
		 * Do each round.
		 */
		kl = kl1;
		kr = kr1;
		round = 16;
		while (round--) {
			/*
			 * Expand R to 48 bits (simulate the E-box).
			 */
			r48l	= ((r & 0x00000001) << 23)
				| ((r & 0xf8000000) >> 9)
				| ((r & 0x1f800000) >> 11)
				| ((r & 0x01f80000) >> 13)
				| ((r & 0x001f8000) >> 15);

			r48r	= ((r & 0x0001f800) << 7)
				| ((r & 0x00001f80) << 5)
				| ((r & 0x000001f8) << 3)
				| ((r & 0x0000001f) << 1)
				| ((r & 0x80000000) >> 31);
			/*
			 * Do salting for crypt() and friends, and
			 * XOR with the permuted key.
			 */
			f = (r48l ^ r48r) & saltbits;
			r48l ^= f ^ *kl++;
			r48r ^= f ^ *kr++;
			/*
			 * Do sbox lookups (which shrink it back to 32 bits)
			 * and do the pbox permutation at the same time.
			 */
			f = psbox_flat[(0*256) + m_sbox_flat[(0*4096) + (r48l >> 12)]]
			  | psbox_flat[(1*256) + m_sbox_flat[(1*4096) + (r48l & 0xfff)]]
			  | psbox_flat[(2*256) + m_sbox_flat[(2*4096) + (r48r >> 12)]]
			  | psbox_flat[(3*256) + m_sbox_flat[(3*4096) + (r48r & 0xfff)]];
			/*
			 * Now that we've permuted things, complete f().
			 */
			f ^= l;
			l = r;
			r = f;
		}
		r = l;
		l = f;
	}
	/*
	 * Do final permutation (inverse of IP).
	 */
	*l_out	= fp_maskl_flat[(0*256) + (l >> 24)]
		| fp_maskl_flat[(1*256) + ((l >> 16) & 0xff)]
		| fp_maskl_flat[(2*256) + ((l >> 8) & 0xff)]
		| fp_maskl_flat[(3*256) + (l & 0xff)]
		| fp_maskl_flat[(4*256) + (r >> 24)]
		| fp_maskl_flat[(5*256) + ((r >> 16) & 0xff)]
		| fp_maskl_flat[(6*256) + ((r >> 8) & 0xff)]
		| fp_maskl_flat[(7*256) + (r & 0xff)];
	*r_out	= fp_maskr_flat[(0*256) + (l >> 24)]
		| fp_maskr_flat[(1*256) + ((l >> 16) & 0xff)]
		| fp_maskr_flat[(2*256) + ((l >> 8) & 0xff)]
		| fp_maskr_flat[(3*256) + (l & 0xff)]
		| fp_maskr_flat[(4*256) + (r >> 24)]
		| fp_maskr_flat[(5*256) + ((r >> 16) & 0xff)]
		| fp_maskr_flat[(6*256) + ((r >> 8) & 0xff)]
		| fp_maskr_flat[(7*256) + (r & 0xff)];
    #ifdef debug
    printf("l, r\n");
    printf("%u\n", *l_out);
    printf("%u\n", *r_out); 
    #endif
    return(0);	
}


char * __crypt_extended_r(__global uchar *m_sbox_flat,
                        __global uint *psbox_flat,
                        __global uint *ip_maskl_flat,
                        __global uint *ip_maskr_flat,
                        __global uint *fp_maskl_flat,
                        __global uint *fp_maskr_flat,
                        __global uint *key_perm_maskl_flat,
                        __global uint *key_perm_maskr_flat,
                        __global uint *comp_maskl_flat,
                        __global uint *comp_maskr_flat,
                        __private char *key,
                        __private char *setting,
                        __private uint *data_saltbits,
                        __private uint *data_old_salt,
                        __private uint *data_en_keysl,
                        __private uint *data_en_keysr,
                        __private uint *data_de_keysl,
                        __private uint *data_de_keysr,
                        __private uint *data_old_rawkey0,
                        __private uint *data_old_rawkey1,
                        __private char *data_output
                        )                       
{
    #ifdef debug
    int k; 
    printf("initial output\n");
    printf("\n");
    #endif

    char	ascii64[] =
	 "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

    int i;
    uint	count, salt, l, r0, r1, keybuf[2];
    uchar *p, *q;
    /* skipping initialization */
	/*
	 * Copy the key, shifting each character up by one bit
	 * and padding with zeros.
	 */
	q = (uchar *) keybuf;
	while (q - (uchar *) keybuf < sizeof(keybuf)) {
		*q++ = *key << 1;
		if (*key)
			key++;
	}
    
    des_setkey(key_perm_maskl_flat,
               key_perm_maskr_flat,
               comp_maskl_flat,
               comp_maskr_flat,
               keybuf, 
               data_en_keysl,
               data_en_keysr,
               data_de_keysl,
               data_de_keysr,
               data_old_rawkey0,
               data_old_rawkey1,
               data_output
              );
    #ifdef debug
    printf("output after setkey\n");
    for (k = 0; k < 16; k++)
        printf("%u", data_en_keysl[k]);
    printf("\n");

    printf("%s\n", data_output);
    #endif 
    /*
     * "old"-style:
     *	setting - 2 chars of salt
     *	key - up to 8 characters
     */
    count = 25;
    

    salt = (ascii_to_bin(setting[1]) << 6)
         |  ascii_to_bin(setting[0]);

    data_output[0] = 1;
    data_output[1] = 1;
    p = (uchar *) data_output + 2;
    #ifdef debug
    printf("output before setup_salt\n");
    printf("%s\n", data_output);
    for (k = 0; k < 8; k++)
        printf("%u", data_output[k]);
    printf("\n");
    #endif
    setup_salt(salt, data_saltbits, data_old_salt);
    #ifdef debug
    printf("output after setup_salt\n");
    printf("%u\n", *data_saltbits);
    printf("%u\n", *data_old_salt);
    #endif
  	/*
	 * Do it.
	 */
    do_des(m_sbox_flat,
           psbox_flat,
           ip_maskl_flat,
           ip_maskr_flat,
           fp_maskl_flat,
           fp_maskr_flat,
           0, 
           0, 
           &r0,
           &r1,
           count,
           data_saltbits,
           data_en_keysl,
           data_en_keysr,
           data_de_keysl,
           data_de_keysr
           );
	/*
	 * Now encode the result...
	 */
     
	l = (r0 >> 8);
	p[0] = ascii64[(l >> 18) & 0x3f];
	p[1] = ascii64[(l >> 12) & 0x3f];
	p[2] = ascii64[(l >> 6) & 0x3f];
	p[3] = ascii64[l & 0x3f];

	l = (r0 << 16) | ((r1 >> 16) & 0xffff);
	p[4] = ascii64[(l >> 18) & 0x3f];
	p[5] = ascii64[(l >> 12) & 0x3f];
	p[6] = ascii64[(l >> 6) & 0x3f];
	p[7] = ascii64[l & 0x3f];

	l = r1 << 2;
	p[8] = ascii64[(l >> 12) & 0x3f];
	p[9] = ascii64[(l >> 6) & 0x3f];
	p[10] = ascii64[l & 0x3f];
	p[11] = 0;

	return(data_output);
}

inline int strstr(__private char *target, __private char *src)
{
    int i;
    int j;
    for (i = 0; target[i]; i++)
    {
        j = 0;
        while (target[i+j] == src[j])
        {
            if (!src[j+1])
                return 1;
            else
                j++;
        }
    } 
    return 0;
}

inline int strlen(__private char *str)
{
    int i = 0;
    while(str[i++]);
    return i-1;
}

inline void shifterino(__private char *hash)
{
    int i;
    int start = strlen(hash) - TRUNCATE_LEN;
    for (i = 0; i <= TRUNCATE_LEN; i++)
    {
        hash[i] = hash[start + i];
    }
}

inline void salterino(__private char *pw, __private char *salt)
{
    salt[0] = pw[1];
    salt[1] = pw[2];
    salt[2] = '\0';
    if (salt[0] < VALID_MIN || salt[0] > VALID_MAX)
        salt[0] = '.';
    if (salt[1] < VALID_MIN || salt[1] > VALID_MAX)
        salt[0] = '.';

    if (salt[0] >= REPLACE_MIN && salt[0] <= REPLACE_MAX)
        salt[0] += REPLACE_OFFSET;
    else if (salt[0] >= REPLACE_MIN_2 && salt[0] <= REPLACE_MAX_2)
        salt[0] += REPLACE_OFFSET_2; 

    if (salt[1] >= REPLACE_MIN && salt[1] <= REPLACE_MAX)
        salt[1] += REPLACE_OFFSET;
    else if (salt[1] >= REPLACE_MIN_2 && salt[1] <= REPLACE_MAX_2)
        salt[1] += REPLACE_OFFSET_2; 
}

inline void generate_pw_fast(__private uint *x,
                      __private uint *y, 
                      __private uint *z, 
                      __private uint *w,\
char *pw)
{
    int i = 0;
    int end = 0;
    int cur; 
    uint t;
    for (i = 0; i < MAX_PW_LEN; i++)
    {
        t = *x ^ (*x << 11);
        *x = *y; *y = *z; *z = *w;
        *w = *w ^ (*w >> 19) ^ t ^ (t >> 8);
        
        cur = *w  % (VALID_LEN + 2) - 1; 
        if (cur >= 0)
        {
            pw[end] = cur + VALID_MIN;
            end++;
        }
    }
    pw[end] = '\0';
}

__kernel
void triperino(__global uchar *m_sbox_flat,
          __global uint *psbox_flat,
          __global uint *ip_maskl_flat,
          __global uint *ip_maskr_flat,
          __global uint *fp_maskl_flat,
          __global uint *fp_maskr_flat,
          __global uint *key_perm_maskl_flat,
          __global uint *key_perm_maskr_flat,
          __global uint *comp_maskl_flat,
          __global uint *comp_maskr_flat,
          __global uchar *pw,
          __global uchar *hash)
{
     uint data_saltbits = 0;
    uint data_old_salt = 0;
    uint data_en_keysl[16] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    uint data_en_keysr[16] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    uint data_de_keysl[16] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    uint data_de_keysr[16] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    uint data_old_rawkey0 = 0; 
    uint data_old_rawkey1 = 0;
    char data_output[21] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    char key[] = "asdfasdf";
    char setting[3];
    char *output;
    int idx = get_global_id(0);
    uint x, y, z, w;
    x = idx + 100;
    y = idx + 200;
    z = idx + 300;
    w = idx + 400;
    

    char test[] = "TESTERINO";
    if (idx == 0 && strstr((char *)hash, test))
    {    
        char key1[] = "tripcode";
        salterino(key1, setting);
        char test1[] = "3GqYIJ3Obs";

    char *output = __crypt_extended_r(m_sbox_flat,
                       psbox_flat,
                       ip_maskl_flat,
                       ip_maskr_flat,
                       fp_maskl_flat,
                       fp_maskr_flat,
                       key_perm_maskl_flat,
                       key_perm_maskr_flat,
                       comp_maskl_flat,
                       comp_maskr_flat,
        key1, setting, &data_saltbits, &data_old_salt,\
        data_en_keysl, data_en_keysr, data_de_keysl, data_de_keysr,\
        &data_old_rawkey0, &data_old_rawkey1, data_output);
   
        shifterino((char *) data_output); 
        int c;
        for (c = 0; c < 21; c++)
        {
            pw[c] = data_output[c]; 
        }
        printf("%s\n", data_output);
        if (strstr((char *) data_output, test1))
            printf("TEST 1 PASSED\n");
        else
            printf("TEST 1 FAILED\n");
    }
    else
    {
        int i = 0;
        while (i < 1000000)
        {
            generate_pw_fast(&x, &y, &z, &w, (char *) key);

            salterino(key, setting);
            output = __crypt_extended_r(m_sbox_flat,
                       psbox_flat,
                       ip_maskl_flat,
                       ip_maskr_flat,
                       fp_maskl_flat,
                       fp_maskr_flat,
                       key_perm_maskl_flat,
                       key_perm_maskr_flat,
                       comp_maskl_flat,
                       comp_maskr_flat,
        key, setting, &data_saltbits, &data_old_salt,\
        data_en_keysl, data_en_keysr, data_de_keysl, data_de_keysr,\
        &data_old_rawkey0, &data_old_rawkey1, data_output);
        char pat[] = "COOL"; 
        shifterino((char *) data_output); 
        if (strstr((char *) data_output, pat))
            printf("%s...\%s\n", key, data_output);
            i++;
        } 
    }
} 
