package com.zuhoocms.auth.user;

import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.authentication.LockedException;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class UserDetailsServiceImpl implements UserDetailsService {

    private final UserRepository userRepository;

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {

        User user = userRepository.findByEmail(username)
                .orElseThrow(()-> new UsernameNotFoundException(
                        "User not found with email: " + username
                ));
        String roleAuthority = "ROLE_" + user.getRole().name();

        if (!user.isActive()) {
            throw new DisabledException(
                    "Your account is inactive. Please contact admin."
            );
        }

        // Checked explicitly because the Spring Security User returned below reports isAccountNonLocked()/isEnabled() true regardless of the domain entity, so LoginAttemptService's lockout would never be enforced.
        if (user.getLockedUntil() != null && user.getLockedUntil().isAfter(LocalDateTime.now())) {
            throw new LockedException(
                    "Too many failed login attempts. Please try again later."
            );
        }

        return new org.springframework.security.core.userdetails.User(
                user.getEmail(),
                user.getPassword(),
                List.of(new SimpleGrantedAuthority(roleAuthority))
        );

    }

}
